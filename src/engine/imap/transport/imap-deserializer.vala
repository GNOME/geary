/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * The Deserializer performs asynchronous I/O on a supplied input stream and transforms the raw
 * bytes into IMAP {@link Parameter}s (which can then be converted into {@link ServerResponse}s or
 * {@link ServerData}).
 *
 * The Deserializer will only begin reading from the stream when {@link start_async} is called.
 * Calling {@link stop_async} will halt reading without closing the stream itself.  A Deserializer
 * may not be reused once stop_async has been invoked.
 *
 * Since all results from the Deserializer are reported via signals, those signals should be
 * connected to prior to calling start_async, or the caller risks missing early messages.  (Note
 * that since Deserializer uses async I/O, this isn't technically possible unless the signals are
 * connected after the Idle loop has a chance to run; however, this is an implementation detail and
 * shouldn't be relied upon.)
 *
 * Internally Deserializer uses a DataInputStream to help decode the data.  Since DataInputStream
 * is buffered, there's no need to buffer the InputStream passed to Deserializer's constructor.
 */

public class Geary.Imap.Deserializer : BaseObject, Logging.Source {


    private const size_t MAX_BLOCK_READ_SIZE = 4096;

    private const string[] RESPONSE_ATOMS = {
        "OK", "NO", "BAD", "BYE", "PREAUTH"
    };

    private enum Mode {
        LINE,
        BLOCK,
        FAILED,
        CLOSED
    }

    private enum State {
        TAG,
        START_PARAM,
        ATOM,
        FLAG,
        QUOTED,
        QUOTED_ESCAPE,
        PARTIAL_BODY_ATOM,
        PARTIAL_BODY_ATOM_TERMINATING,
        LITERAL,
        LITERAL_DATA_BEGIN,
        LITERAL_DATA,
        RESPONSE_TEXT,
        FAILED,
        CLOSED,
        COUNT
    }

    private static string state_to_string(uint state) {
        return ((State) state).to_string();
    }

    private enum Event {
        CHAR,
        EOL,
        DATA,
        EOS,
        ERROR,
        COUNT
    }

    private static string event_to_string(uint event) {
        return ((Event) event).to_string();
    }

    private static Geary.State.MachineDescriptor machine_desc = new Geary.State.MachineDescriptor(
        "Geary.Imap.Deserializer", State.TAG, State.COUNT, Event.COUNT,
        state_to_string, event_to_string);

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return ClientService.DESERIALISATION_LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;

    /** The quirks being used by this deserializer. */
    internal Quirks quirks { get; set; }

    private string identifier;
    private DataInputStream input;
    private Geary.State.Machine fsm;

    private ListParameter context;
    private Gee.LinkedList<ListParameter> context_stack =
        new Gee.LinkedList<ListParameter>();

    private Cancellable? cancellable = null;
    private Nonblocking.Semaphore closed_semaphore = new Nonblocking.Semaphore();
    private StringBuilder? current_string = null;
    private size_t literal_length_remaining = 0;
    private Geary.Memory.GrowableBuffer? block_buffer = null;
    private unowned uint8[]? current_buffer = null;
    private int ins_priority = Priority.DEFAULT;

    private bool is_parsing_flags = false;


    /**
     * Fired when a complete set of IMAP {@link Parameter}s have been received.
     *
     * Note that {@link RootParameters} may contain {@link QuotedStringParameter}s,
     * {@link UnquotedStringParameter}s, {@link ResponseCode}, and {@link ListParameter}s.
     * Deserializer does not produce any other kind of Parameter due to its inability to deduce
     * them from syntax alone.  ResponseCode, however, can be.
     *
     * All strings are ASCII (7-bit) with control characters stripped (with the exception of
     * {@link QuotedStringParameter} which allows for some control characters).
     */
    public signal void parameters_ready(RootParameters root);

    /**
     * Fired as data blocks are received during download.
     *
     * The bytes themselves may be partial and unusable out of context, so they're not provided,
     * but their size is, to allow monitoring of speed and such.
     *
     * Note that this is fired for both line data (i.e. responses, status, etc.) and literal data
     * (block transfers).
     *
     * In general, this signal is provided to inform subscribers that activity is happening
     * on the receive channel, especially during long downloads.
     */
    public signal void bytes_received(size_t bytes);

    /**
     * Fired when a syntax error has occurred.
     *
     * This generally means the data looks like garbage and further
     * deserialization is unlikely or impossible.
     */
    public signal void deserialize_failure();

    /**
     * Fired when an Error is trapped on the input stream.
     *
     * This is nonrecoverable and means the stream should be closed
     * and this Deserializer destroyed.
     */
    public signal void receive_failure(GLib.Error err);

    /**
     * Fired when the underlying InputStream is closed.
     *
     * This is nonrecoverable and means the stream should be closed
     * and this Deserializer destroyed.
     */
    public signal void end_of_stream();


    public Deserializer(string identifier,
                        GLib.InputStream input,
                        Quirks quirks) {
        this.identifier = identifier;

        this.input = new GLib.DataInputStream(input);
        this.input.set_close_base_stream(false);
        this.input.set_newline_type(CR_LF);

        this.quirks = quirks;

        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.TAG, Event.CHAR, on_tag_char),
            new Geary.State.Mapping(State.TAG, Event.EOS, on_eos),
            new Geary.State.Mapping(State.TAG, Event.ERROR, on_error),

            new Geary.State.Mapping(State.START_PARAM, Event.CHAR, on_first_param_char),
            new Geary.State.Mapping(State.START_PARAM, Event.EOL, on_eol),
            new Geary.State.Mapping(State.START_PARAM, Event.EOS, on_eos),
            new Geary.State.Mapping(State.START_PARAM, Event.ERROR, on_error),

            new Geary.State.Mapping(State.ATOM, Event.CHAR, on_atom_char),
            new Geary.State.Mapping(State.ATOM, Event.EOL, on_param_eol),
            new Geary.State.Mapping(State.ATOM, Event.EOS, on_eos),
            new Geary.State.Mapping(State.ATOM, Event.ERROR, on_error),

            new Geary.State.Mapping(State.FLAG, Event.CHAR, on_flag_char),
            new Geary.State.Mapping(State.FLAG, Event.EOL, on_param_eol),
            new Geary.State.Mapping(State.FLAG, Event.EOS, on_eos),
            new Geary.State.Mapping(State.FLAG, Event.ERROR, on_error),

            new Geary.State.Mapping(State.QUOTED, Event.CHAR, on_quoted_char),
            new Geary.State.Mapping(State.QUOTED, Event.EOS, on_eos),
            new Geary.State.Mapping(State.QUOTED, Event.ERROR, on_error),

            new Geary.State.Mapping(State.QUOTED_ESCAPE, Event.CHAR, on_quoted_escape_char),
            new Geary.State.Mapping(State.QUOTED_ESCAPE, Event.EOS, on_eos),
            new Geary.State.Mapping(State.QUOTED_ESCAPE, Event.ERROR, on_error),

            new Geary.State.Mapping(State.PARTIAL_BODY_ATOM, Event.CHAR, on_partial_body_atom_char),
            new Geary.State.Mapping(State.PARTIAL_BODY_ATOM, Event.EOS, on_eos),
            new Geary.State.Mapping(State.PARTIAL_BODY_ATOM, Event.ERROR, on_error),

            new Geary.State.Mapping(State.PARTIAL_BODY_ATOM_TERMINATING, Event.CHAR,
                on_partial_body_atom_terminating_char),
            new Geary.State.Mapping(State.PARTIAL_BODY_ATOM_TERMINATING, Event.EOS, on_eos),
            new Geary.State.Mapping(State.PARTIAL_BODY_ATOM_TERMINATING, Event.ERROR, on_error),

            new Geary.State.Mapping(State.LITERAL, Event.CHAR, on_literal_char),
            new Geary.State.Mapping(State.LITERAL, Event.EOS, on_eos),
            new Geary.State.Mapping(State.LITERAL, Event.ERROR, on_error),

            new Geary.State.Mapping(State.LITERAL_DATA_BEGIN, Event.EOL, on_literal_data_begin_eol),
            new Geary.State.Mapping(State.LITERAL_DATA_BEGIN, Event.EOS, on_eos),
            new Geary.State.Mapping(State.LITERAL_DATA_BEGIN, Event.ERROR, on_error),

            new Geary.State.Mapping(State.LITERAL_DATA, Event.DATA, on_literal_data),
            new Geary.State.Mapping(State.LITERAL_DATA, Event.EOS, on_eos),
            new Geary.State.Mapping(State.LITERAL_DATA, Event.ERROR, on_error),

            new Geary.State.Mapping(State.RESPONSE_TEXT, Event.CHAR, on_response_text_char),
            new Geary.State.Mapping(State.RESPONSE_TEXT, Event.EOL, on_param_eol),
            new Geary.State.Mapping(State.RESPONSE_TEXT, Event.EOS, on_eos),
            new Geary.State.Mapping(State.RESPONSE_TEXT, Event.ERROR, on_error),

            new Geary.State.Mapping(State.FAILED, Event.EOL, on_failed_eol),
            new Geary.State.Mapping(State.FAILED, Event.EOS, Geary.State.nop),
            new Geary.State.Mapping(State.FAILED, Event.ERROR, Geary.State.nop),

            new Geary.State.Mapping(State.CLOSED, Event.EOS, Geary.State.nop),
            new Geary.State.Mapping(State.CLOSED, Event.ERROR, Geary.State.nop)
        };

        this.fsm = new Geary.State.Machine(machine_desc, mappings, on_bad_transition);

        reset_params();
    }

    /**
     * Begin deserializing IMAP responses from the input stream.
     *
     * Subscribe to the various signals before starting to ensure that all responses are trapped.
     */
    public async void start_async(int priority = GLib.Priority.DEFAULT_IDLE) throws Error {
        if (cancellable != null)
            throw new EngineError.ALREADY_OPEN("Deserializer already open");

        Mode mode = get_mode();

        if (mode == Mode.FAILED)
            throw new EngineError.ALREADY_CLOSED("Deserializer failed");

        if ((mode == Mode.CLOSED) || (cancellable != null && cancellable.is_cancelled()))
            throw new EngineError.ALREADY_CLOSED("Deserializer closed");

        cancellable = new Cancellable();
        ins_priority = priority;

        next_deserialize_step();
    }

    public async void stop_async() throws Error {
        // quietly fail when not opened or already closed
        if (cancellable == null || cancellable.is_cancelled() || is_halted())
            return;

        // cancel any outstanding I/O
        cancellable.cancel();

        // wait for outstanding I/O to exit
        yield closed_semaphore.wait_async();
        yield this.input.close_async(GLib.Priority.DEFAULT, null);
        debug("Deserializer closed");
    }

    /**
     * Determines if the deserializer is closed.
     */
    public bool is_halted() {
        switch (get_mode()) {
            case Mode.FAILED:
            case Mode.CLOSED:
                return true;

            default:
                return false;
        }
    }

    /** {@inheritDoc} */
    public Logging.State to_logging_state() {
        return new Logging.State(this, fsm.get_state_string(fsm.state));
    }

    /** Sets the connection's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    private void next_deserialize_step() {
        switch (get_mode()) {
            case Mode.LINE:
                this.input.read_line_async.begin(
                    ins_priority, cancellable, on_read_line
                );
            break;

            case Mode.BLOCK:
                // Can't merely skip zero-byte literal, need to go through async transaction to
                // properly send events to the FSM
                assert(literal_length_remaining >= 0);

                if (block_buffer == null)
                    block_buffer = new Geary.Memory.GrowableBuffer();

                current_buffer = block_buffer.allocate(
                    size_t.min(MAX_BLOCK_READ_SIZE, literal_length_remaining));

                this.input.read_async.begin(
                    current_buffer, ins_priority, cancellable, on_read_block
                );
            break;

            case Mode.FAILED:
            case Mode.CLOSED:
                // do nothing; Deserializer is effectively closed
            break;

            default:
                assert_not_reached();
        }
    }

    private void on_read_line(Object? source, AsyncResult result) {
        try {
            size_t bytes_read;
            string? line = this.input.read_line_async.end(
                result, out bytes_read
            );
            if (line == null) {
                debug("Line EOS");
                push_eos();
                return;
            }

            debug("Line: %s", line);
            bytes_received(bytes_read);
            push_line(line, bytes_read);
        } catch (Error err) {
            push_error(err);
            return;
        }

        next_deserialize_step();
    }

    private void on_read_block(Object? source, AsyncResult result) {
        try {
            // Zero-byte literals are legal (see note in next_deserialize_step()), so EOS only
            // happens when actually pulling data
            size_t bytes_read = this.input.read_async.end(result);
            if (bytes_read == 0 && literal_length_remaining > 0) {
                debug("Block EOS");

                push_eos();

                return;
            }

            debug("Block %lub", bytes_read);
            bytes_received(bytes_read);

            // adjust the current buffer's size to the amount that was actually read in
            block_buffer.trim(current_buffer, bytes_read);

            push_data(bytes_read);
        } catch (Error err) {
            push_error(err);

            return;
        }

        next_deserialize_step();
    }

    // Push a line (without the CRLF!).  Because DataInputStream reads to EOL but accepts all other
    // characters, it's possible for NULs to be embedded in the string, so the count must be passed
    // as well (and shouldn't be -1!)
    private void push_line(string line, size_t count) {
        assert(get_mode() == Mode.LINE);

        for (long ctr = 0; ctr < count; ctr++) {
            char ch = line[ctr];
            if (ch == '\0') {
                // drop on the floor; IMAP spec does not allow NUL in lines at all, see
                // http://tools.ietf.org/html/rfc3501#section-9 note 3.
                continue;
            }

            if (fsm.issue(Event.CHAR, &ch) == State.FAILED) {
                // Don't try to continue processing, but continue to
                // EOL regardless for cleanup.
                break;
            }
        }

        fsm.issue(Event.EOL);
    }

    // Push a block of literal data
    private void push_data(size_t bytes_read) {
        assert(get_mode() == Mode.BLOCK);
        fsm.issue(Event.DATA, &bytes_read);
    }

    // Push an EOS event
    private void push_eos() {
        fsm.issue(Event.EOS);
    }

    // Push an Error event
    private void push_error(Error err) {
        fsm.issue(Event.ERROR, null, null, err);
    }

    private Mode get_mode() {
        switch (fsm.state) {
            case State.LITERAL_DATA:
                return Mode.BLOCK;

            case State.FAILED:
                return Mode.FAILED;

            case State.CLOSED:
                return Mode.CLOSED;

            default:
                return Mode.LINE;
        }
    }

    private inline  bool is_current_string_empty() {
        return (
            this.current_string == null || this.current_string.len == 0
        );
    }

    // Case-insensitive compare
    private inline bool is_current_string_ci(string cmp) {
        if (this.current_string == null ||
            this.current_string.len != cmp.length) {
            return false;
        }

        return Ascii.stri_equal(this.current_string.str, cmp);
    }

    private inline void append_to_string(char ch) {
        if (this.current_string == null) {
            this.current_string = new StringBuilder();
        }

        this.current_string.append_c(ch);
    }

    private void save_string_parameter(bool quoted) {
        // deal with empty strings
        if (!quoted && is_current_string_empty())
            return;

        // deal with empty quoted strings
        string str = (quoted && current_string == null) ? "" : current_string.str;

        if (quoted)
            save_parameter(new QuotedStringParameter(str));
        else if (NumberParameter.is_ascii_numeric(str, null))
            save_parameter(new NumberParameter.from_ascii(str));
        else
            save_parameter(new UnquotedStringParameter(str));

        current_string = null;
    }

    private void save_literal_parameter() {
        var literal = new LiteralParameter(block_buffer);
        if (!Logging.is_suppressed_domain(this.logging_domain)) {
            debug(literal.coerce_to_string_parameter().to_string());
        }
        save_parameter(literal);
        block_buffer = null;
    }

    private void save_parameter(Parameter param) {
        context.add(param);
    }

    // ListParameter's parent *must* be current context
    private void push(ListParameter child) {
        this.context.add(child);

        this.context_stack.insert(0, child);
        this.context = child;
    }

    private char get_current_context_terminator() {
        return (context is ResponseCode) ? ']' : ')';
    }

    private State pop() {
        State ret = State.START_PARAM;
        if (this.context_stack.size > 1) {
            this.context_stack.remove_at(0);
            this.context = this.context_stack[0];
        } else {
            warning("Attempt to close unopened list/response code");
            ret = State.FAILED;
        }
        return ret;
    }

    private void flush_params() {
        bool okay = true;
        if (this.context_stack.size > 1) {
            debug("Unclosed list in parameters");
            okay = false;
        }

        if (!is_current_string_empty() || this.literal_length_remaining > 0) {
            debug(
                "Unfinished parameter: string=%s literal remaining=%lu",
                (!is_current_string_empty()).to_string(),
                this.literal_length_remaining
            );
            okay = false;
        }

        if (okay && this.context.size > 0) {
            parameters_ready((RootParameters) this.context);
        }

        reset_params();
    }

    private void reset_params() {
        this.context = new RootParameters();
        this.context_stack.clear();
        this.context_stack.add(this.context);
    }

    //
    // Transition handlers
    //

    private uint on_first_param_char(uint state, uint event, void *user) {
        // look for opening characters to special parameter formats, otherwise jump to atom
        // handler (i.e. don't drop this character in the case of atoms)
        char ch = *((char *) user);
        switch (ch) {
            case '[':
                // "[" is a valid character for flags (and used by Gmail)
                if (this.is_parsing_flags) {
                    append_to_string(ch);
                    return State.FLAG;
                }

                // open response code
                ResponseCode response_code = new ResponseCode();
                push(response_code);
                return State.START_PARAM;

            case ']':
                if (ch != get_current_context_terminator()) {
                    if (state == State.ATOM) {
                        // Allow ']' in atom IFF it does not close the context
                        // this is to allow [] in folder names
                        append_to_string(ch);
                        return State.ATOM;
                    }
                    warning("Received an unexpected closing brace");
                    return State.FAILED;
                }
                return pop();

            case '{':
                return State.LITERAL;

            case '\"':
                return State.QUOTED;

            case '(':
                // open list
                ListParameter list = new ListParameter();
                push(list);
                return State.START_PARAM;

            case ')':
                if (ch != get_current_context_terminator()) {
                    warning("Received an unexpected closing parens");
                    return State.FAILED;
                }
                this.is_parsing_flags = false;
                return pop();

            case '\\':
                // Start of a flag
                append_to_string(ch);
                this.is_parsing_flags = true;
                return State.FLAG;

            case ' ':
                // just consume the space
                return State.START_PARAM;

            default:
                if (this.context_stack.size == 1 &&
                    this.context.size >= 2 &&
                    this.context.get(1).to_string().ascii_up() in RESPONSE_ATOMS) {
                    append_to_string(ch);
                    return State.RESPONSE_TEXT;
                } else if (!this.is_parsing_flags) {
                    if (DataFormat.is_atom_special(ch)) {
                        warning("Received an invalid atom-char: %c", ch);
                        return State.FAILED;
                    }
                    append_to_string(ch);
                    return State.ATOM;
                } else {
                    if (DataFormat.is_atom_special(
                            ch, this.quirks.flag_atom_exceptions)) {
                        warning("Received an invalid flag-char: %c", ch);
                        return State.FAILED;
                    }
                    append_to_string(ch);
                    return State.FLAG;
                }
        }
    }

    private uint on_tag_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        if (is_current_string_empty() &&
            (ch == '*' || ch == '+')) {
            // At first tag character. Allow a single `*` to indicate
            // an untagged response or a `+` here for continuations
            append_to_string(ch);
            return State.TAG;
        }

        // Any tag special here indicates end-of-tag, so save and work
        // out where to go next
        if (DataFormat.is_tag_special(ch)) {
            save_string_parameter(false);
            return on_first_param_char(state, event, user);
        }

        append_to_string(ch);
        return State.TAG;
    }

    private uint on_atom_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        // The partial body fetch results ("BODY[section]" or "BODY[section]<partial>" and their
        // .peek variants) offer so many exceptions to the decoding process they're given their own
        // state
        if (ch == '[' && (is_current_string_ci("body") || is_current_string_ci("body.peek"))) {
            append_to_string(ch);
            return State.PARTIAL_BODY_ATOM;
        }

        // Any of the atom specials indicate end of atom, so save and
        // work out where to go next
        if (DataFormat.is_atom_special(ch)) {
            save_string_parameter(false);
            return on_first_param_char(state, event, user);
        }

        append_to_string(ch);
        return State.ATOM;
    }

    // Although flags basically have the form "\atom", the special
    // flag "\*" isn't a valid atom, and hence we need a special case
    // for it.
    private uint on_flag_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        if (is_current_string_ci("\\")) {
            // At the start of the flag.
            //
            // Check for special flag "\*", which also indicates
            // end-of-flag
            if (ch == '*') {
                append_to_string(ch);
                save_string_parameter(false);
                return State.START_PARAM;
            }

            // Any of the atom specials indicate end of atom, but we are
            // at the first char after a "\" and a flag has to have at
            // least one atom char to be valid, so if we get an
            // atom-special here bail out.
            if (DataFormat.is_atom_special(ch, this.quirks.flag_atom_exceptions)) {
                warning("Empty flag atom");
                return State.FAILED;
            }
        }

        // Any of the atom specials indicate end of atom, so save
        // and work out where to go next
        if (DataFormat.is_atom_special(ch, this.quirks.flag_atom_exceptions)) {
            save_string_parameter(false);
            return on_first_param_char(state, event, user);
        }

        // Valid flag char, so append and continue
        append_to_string(ch);
        return State.FLAG;
    }

    private uint on_eol(uint state, uint event, void *user) {
        flush_params();
        return State.TAG;
    }

    private uint on_param_eol(uint state, uint event, void *user) {
        // clean up final atom
        save_string_parameter(false);
        flush_params();
        return State.TAG;
    }

    private uint on_failed_eol(uint state, uint event, void *user) {
        // We don't go into the error state on syntax error, merely
        // reset, cross our fingers and hope for the best. Maybe
        // there's a better strategy though?
        debug("Syntax error, dropping");
        deserialize_failure();
        reset_params();
        return State.TAG;
    }

    private uint on_quoted_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        // drop anything above 0x7F, NUL, CR, and LF
        if (ch > 0x7F || ch == '\0' || ch == '\r' || ch == '\n')
            return State.QUOTED;

        // look for escaped characters
        if (ch == '\\')
            return State.QUOTED_ESCAPE;

        // DQUOTE ends quoted string and return to parsing atoms
        if (ch == '\"') {
            save_string_parameter(true);

            return State.START_PARAM;
        }

        append_to_string(ch);

        return State.QUOTED;
    }

    private uint on_quoted_escape_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        // only two accepted escaped characters: double-quote and backslash
        // everything else dropped on the floor
        switch (ch) {
            case '\"':
            case '\\':
                append_to_string(ch);
            break;
        }

        return State.QUOTED;
    }

    private uint on_partial_body_atom_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        // decoding the partial body parameter ("BODY[section]" et al.) is simply to locate the
        // terminating space after the closing square bracket or closing angle bracket
        // TODO: stricter testing of atom special characters and such (much like on_tag_or_atom_char)
        // but keeping in mind the looser rules and such with this variation
        append_to_string(ch);

        // Can't terminate the atom with a close square bracket because the partial span
        // ("<...>") might be next
        //
        // Don't terminate with a close angle bracket unless the next character is a space
        // (which it better be) because the handler needs to eat the space before transitioning
        // to START_PARAM
        switch (ch) {
            case ']':
            case '>':
                return State.PARTIAL_BODY_ATOM_TERMINATING;

            default:
                return state;
        }
    }

    private uint on_partial_body_atom_terminating_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        // anything but a space indicates the atom is continuing, therefore return to prior state
        if (ch != ' ')
            return on_partial_body_atom_char(State.PARTIAL_BODY_ATOM, event, user);

        save_string_parameter(false);

        return State.START_PARAM;
    }

    private uint on_literal_char(uint state, uint event, void *user) {
        char ch = *((char *) user);

        // if close-bracket, end of literal length field -- next event must be EOL
        if (ch == '}') {
            // empty literal treated as garbage
            if (is_current_string_empty()) {
                warning("Empty flag atom");
                return State.FAILED;
            }

            literal_length_remaining = (size_t) long.parse(this.current_string.str);
            this.current_string = null;
            if (literal_length_remaining < 0) {
                warning("Negative literal data length %lu", literal_length_remaining);
                return State.FAILED;
            }

            return State.LITERAL_DATA_BEGIN;
        }

        // drop anything non-numeric
        if (!ch.isdigit())
            return State.LITERAL;

        append_to_string(ch);

        return State.LITERAL;
    }

    private uint on_literal_data_begin_eol(uint state, uint event, void *user) {
        return State.LITERAL_DATA;
    }

    private uint on_literal_data(uint state, uint event, void *user) {
        size_t *bytes_read = (size_t *) user;

        assert(*bytes_read <= literal_length_remaining);
        literal_length_remaining -= *bytes_read;

        if (literal_length_remaining > 0)
            return State.LITERAL_DATA;

        save_literal_parameter();

        return State.START_PARAM;
    }

    private uint on_response_text_char(uint state, uint event, void *user) {
        char ch = *((char *) user);
        append_to_string(ch);
        return State.RESPONSE_TEXT;
    }

    private uint on_eos() {
        debug("EOS");

        // Per RFC 3501 7.1.5, we may get a EOS immediately after a
        // BYE, so flush any message being processed.
        // https://tools.ietf.org/html/rfc3501#section-7.1.5
        flush_params();

        // always signal as closed and notify subscribers
        this.closed_semaphore.blind_notify();
        end_of_stream();

        return State.CLOSED;
    }

    private uint on_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);

        // only Cancellable allowed is internal used to notify when closed; all other errors should
        // be reported
        if (!(err is IOError.CANCELLED)) {
            debug("Input error: %s", err.message);
            receive_failure(err);
        }

        // always signal as closed and notify
        this.closed_semaphore.blind_notify();
        return State.CLOSED;
    }

    private uint on_bad_transition(uint state, uint event, void *user) {
        warning("Bad event %s at state %s", event_to_string(event), state_to_string(state));

        return State.FAILED;
    }
}
