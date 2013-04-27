/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The Deserializer performs asynchronous I/O on a supplied input stream and transforms the raw
 * bytes into IMAP Parameters (which can then be converted into ServerResponses or ServerData).
 * The Deserializer will only begin reading from the stream when start_async() is called.  Calling
 * stop_async() will halt reading without closing the stream itself.  A Deserializer may not be
 * reused once stop_async() has been invoked.
 * 
 * Since all results from the Deserializer are reported via signals, those signals should be
 * connected to prior to calling start_async(), or the caller risks missing early messages.  (Note
 * that since Deserializer uses async I/O, this isn't technically possible unless the signals are
 * connected after the Idle loop has a chance to run; however, this is an implementation detail and
 * shouldn't be relied upon.)
 */

public class Geary.Imap.Deserializer : BaseObject {
    private const size_t MAX_BLOCK_READ_SIZE = 4096;
    
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
        QUOTED,
        QUOTED_ESCAPE,
        PARTIAL_BODY_ATOM,
        PARTIAL_BODY_ATOM_TERMINATING,
        LITERAL,
        LITERAL_DATA_BEGIN,
        LITERAL_DATA,
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
    
    private ConverterInputStream cins;
    private DataInputStream dins;
    private Geary.State.Machine fsm;
    private ListParameter context;
    private Cancellable? cancellable = null;
    private Nonblocking.Semaphore closed_semaphore = new Nonblocking.Semaphore();
    private Geary.Stream.MidstreamConverter midstream = new Geary.Stream.MidstreamConverter("Deserializer");
    private RootParameters root = new RootParameters();
    private StringBuilder? current_string = null;
    private size_t literal_length_remaining = 0;
    private Geary.Memory.GrowableBuffer? block_buffer = null;
    private unowned uint8[]? current_buffer = null;
    private int ins_priority = Priority.DEFAULT;
    private char[] atom_specials_exceptions = { ' ', ' ', '\0' };
    
    /**
     * Fired when a complete set of Parameters have been received.  Note that RootParameters may
     * contain StringParameters, ListParameters, NilParameters, and so on.  One special Parameter
     * decoded by Deserializer is ResponseCode, which is structured internally as a ListParameter
     * subclass for convenience when decoding.
     */
    public signal void parameters_ready(RootParameters root);
    
    /**
     * "eos" is fired when the underlying InputStream is closed, whether due to normal EOS or input
     * error.  Subscribe to "receive-failure" to be notified of errors.
     */
    public signal void eos();
    
    public signal void receive_failure(Error err);
    
    /**
     * "data-received" is fired as data blocks are received during download.  The bytes themselves
     * may be partial and unusable out of context, so they're not provided, but their size is, to allow
     * monitoring of speed and such.
     *
     * Note that this is fired for both line data (i.e. responses, status, etc.) and literal data
     * (block transfers).
     *
     * In general, this signal is provided to inform subscribers that activity is happening
     * on the receive channel, especially during long downloads.
     */
    public signal void bytes_received(size_t bytes);
    
    public signal void deserialize_failure();
    
    public Deserializer(InputStream ins) {
        cins = new ConverterInputStream(ins, midstream);
        cins.set_close_base_stream(false);
        dins = new DataInputStream(cins);
        dins.set_newline_type(DataStreamNewlineType.CR_LF);
        dins.set_close_base_stream(false);
        
        context = root;
        
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.TAG, Event.CHAR, on_tag_or_atom_char),
            new Geary.State.Mapping(State.TAG, Event.EOS, on_eos),
            new Geary.State.Mapping(State.TAG, Event.ERROR, on_error),
            
            new Geary.State.Mapping(State.START_PARAM, Event.CHAR, on_first_param_char),
            new Geary.State.Mapping(State.START_PARAM, Event.EOL, on_eol),
            new Geary.State.Mapping(State.START_PARAM, Event.EOS, on_eos),
            new Geary.State.Mapping(State.START_PARAM, Event.ERROR, on_error),
            
            new Geary.State.Mapping(State.ATOM, Event.CHAR, on_tag_or_atom_char),
            new Geary.State.Mapping(State.ATOM, Event.EOL, on_atom_eol),
            new Geary.State.Mapping(State.ATOM, Event.EOS, on_eos),
            new Geary.State.Mapping(State.ATOM, Event.ERROR, on_error),
            
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
            
            new Geary.State.Mapping(State.FAILED, Event.EOS, Geary.State.nop),
            new Geary.State.Mapping(State.FAILED, Event.ERROR, Geary.State.nop),
            
            new Geary.State.Mapping(State.CLOSED, Event.EOS, Geary.State.nop),
            new Geary.State.Mapping(State.CLOSED, Event.ERROR, Geary.State.nop)
        };
        
        fsm = new Geary.State.Machine(machine_desc, mappings, on_bad_transition);
    }
    
    public bool install_converter(Converter converter) {
        return midstream.install(converter);
    }
    
    public async void start_async(int priority = GLib.Priority.DEFAULT) throws Error {
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
        debug("[%s] Waiting for deserializer to close...", to_string());
        yield closed_semaphore.wait_async();
        debug("[%s] Deserializer closed", to_string());
    }
    
    private void next_deserialize_step() {
        switch (get_mode()) {
            case Mode.LINE:
                dins.read_line_async.begin(ins_priority, cancellable, on_read_line);
            break;
            
            case Mode.BLOCK:
                // Can't merely skip zero-byte literal, need to go through async transaction to
                // properly send events to the FSM
                assert(literal_length_remaining >= 0);
                
                if (block_buffer == null)
                    block_buffer = new Geary.Memory.GrowableBuffer();
                
                current_buffer = block_buffer.allocate(
                    size_t.min(MAX_BLOCK_READ_SIZE, literal_length_remaining));
                
                dins.read_async.begin(current_buffer, ins_priority, cancellable, on_read_block);
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
            string? line = dins.read_line_async.end(result, out bytes_read);
            if (line == null) {
                push_eos();
                
                return;
            }
            
            bytes_received(bytes_read);
            
            push_line(line);
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
            size_t bytes_read = dins.read_async.end(result);
            if (bytes_read == 0 && literal_length_remaining > 0) {
                push_eos();
                
                return;
            }
            
            bytes_received(bytes_read);
            
            // adjust the current buffer's size to the amount that was actually read in
            block_buffer.adjust(current_buffer, bytes_read);
            
            push_data(bytes_read);
        } catch (Error err) {
            push_error(err);
            
            return;
        }
        
        next_deserialize_step();
    }
    
    // Push a line (without the CRLF!).
    private Mode push_line(string line) {
        assert(get_mode() == Mode.LINE);
        
        int index = 0;
        unichar ch;
        while (line.get_next_char(ref index, out ch)) {
            if (fsm.issue(Event.CHAR, &ch) == State.FAILED) {
                deserialize_failure();
                
                return Mode.FAILED;
            }
        }
        
        if (fsm.issue(Event.EOL) == State.FAILED) {
            deserialize_failure();
            
            return Mode.FAILED;
        }
        
        return get_mode();
    }
    
    // Push a block of literal data
    private Mode push_data(size_t bytes_read) {
        assert(get_mode() == Mode.BLOCK);
        
        if (fsm.issue(Event.DATA, &bytes_read) == State.FAILED) {
            deserialize_failure();
            
            return Mode.FAILED;
        }
        
        return get_mode();
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
        switch (fsm.get_state()) {
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
    
    // True if the Deserializer is FAILED or CLOSED.
    private bool is_halted() {
        switch (get_mode()) {
            case Mode.FAILED:
            case Mode.CLOSED:
                return true;
            
            default:
                return false;
        }
    }
    
    private bool is_current_string_empty() {
        return (current_string == null) || String.is_empty(current_string.str);
    }
    
    // Case-insensitive compare
    private bool has_current_string_prefix(string prefix) {
        if (current_string == null || String.is_empty(current_string.str))
            return false;
        
        return current_string.str.down().has_prefix(prefix);
    }
    
    private void append_to_string(unichar ch) {
        if (current_string == null)
            current_string = new StringBuilder();
        
        current_string.append_unichar(ch);
    }
    
    private void save_string_parameter() {
        if (is_current_string_empty())
            return;
        
        if (NilParameter.is_nil(current_string.str))
            save_parameter(NilParameter.instance);
        else
            save_parameter(new StringParameter(current_string.str));
        
        current_string = null;
    }
    
    private void clear_string_parameter() {
        current_string = null;
    }
    
    private void save_literal_parameter() {
        save_parameter(new LiteralParameter(block_buffer));
        block_buffer = null;
    }
    
    private void save_parameter(Parameter param) {
        context.add(param);
    }
    
    // ListParameter's parent *must* be current context
    private void push(ListParameter child) {
        assert(child.get_parent() == context);
        context.add(child);
        
        context = child;
    }
    
    private char get_current_context_terminator() {
        return (context is ResponseCode) ? ']' : ')';
    }
    
    private State pop() {
        ListParameter? parent = context.get_parent();
        if (parent == null) {
            warning("Attempt to close unopened list/response code");
            
            return State.FAILED;
        }
        
        context = parent;
        
        return State.START_PARAM;
    }
    
    private State flush_params() {
        if (context != root) {
            warning("Unclosed list in parameters");
            
            return State.FAILED;
        }
        
        if (!is_current_string_empty() || literal_length_remaining > 0) {
            warning("Unfinished parameter: string=%s literal remaining=%lu", 
                (!is_current_string_empty()).to_string(), literal_length_remaining);
            
            return State.FAILED;
        }
        
        RootParameters ready = root;
        root = new RootParameters();
        context = root;
        
        parameters_ready(ready);
        
        return State.TAG;
    }
    
    //
    // Transition handlers
    //
    
    private uint on_first_param_char(uint state, uint event, void *user) {
        // look for opening characters to special parameter formats, otherwise jump to atom
        // handler (i.e. don't drop this character in the case of atoms)
        unichar ch = *((unichar *) user);
        switch (ch) {
            case '[':
                // open response code
                ResponseCode response_code = new ResponseCode(context);
                push(response_code);
                
                return State.START_PARAM;
            
            case '{':
                return State.LITERAL;
            
            case '\"':
                return State.QUOTED;
            
            case '(':
                // open list
                ListParameter list = new ListParameter(context);
                push(list);
                
                return State.START_PARAM;
            
            default:
                // if current context's terminator, close the context, otherwise deserializer is
                // now "in" an Atom
                if (ch == get_current_context_terminator())
                    return pop();
                else
                    return on_tag_or_atom_char(State.ATOM, event, user);
        }
    }
    
    private uint on_eol(uint state, uint event, void *user) {
        return flush_params();
    }
    
    private uint on_tag_or_atom_char(uint state, uint event, void *user) {
        assert(state == State.TAG || state == State.ATOM);
        
        unichar ch = *((unichar *) user);
        
        // The partial body fetch results ("BODY[section]" or "BODY[section]<partial>" and their
        // .peek variants) offer so many exceptions to the decoding process they're given their own
        // state
        if (state == State.ATOM && ch == '['
            && (has_current_string_prefix("body") || has_current_string_prefix("body.peek"))) {
            append_to_string(ch);
            
            return State.PARTIAL_BODY_ATOM;
        }
        
        // get the terminator for this context and re-use the atom_special_exceptions array to
        // pass to DataFormat.is_atom_special() (this means not allocating a new array on the heap
        // for each call here, which isn't a problem because the FSM is non-reentrant)
        char terminator = get_current_context_terminator();
        atom_specials_exceptions[1] = terminator;
        
        // Atom specials includes space and close-parens, but those are handled in particular ways
        // while in the ATOM state, so they're excluded here.  Like atom specials, the space is 
        // treated in a particular way for tags, but unlike atom, the close-parens character is not.
        // The + symbol indicates a continuation and needs to be excepted when searching for a tag.
        if (state == State.TAG && DataFormat.is_tag_special(ch, " +"))
            return state;
        else if (state == State.ATOM && DataFormat.is_atom_special(ch, (string) atom_specials_exceptions))
            return state;
        
        // message flag indicator is only legal at start of atom
        if (state == State.ATOM && ch == '\\' && !is_current_string_empty())
            return state;
        
        // space indicates end-of-atom or end-of-tag
        if (ch == ' ') {
            save_string_parameter();
            
            return State.START_PARAM;
        }
        
        // close-parens/close-square-bracket after an atom indicates end-of-list/end-of-response
        // code
        if (state == State.ATOM && ch == terminator) {
            save_string_parameter();
            
            return pop();
        }
        
        append_to_string(ch);
        
        return state;
    }
    
    private uint on_atom_eol(uint state, uint event, void *user) {
        // clean up final atom
        save_string_parameter();
        
        return flush_params();
    }
    
    private uint on_quoted_char(uint state, uint event, void *user) {
        unichar ch = *((unichar *) user);
        
        // drop anything above 0x7F, NUL, CR, and LF
        if (ch > 0x7F || ch == '\0' || ch == '\r' || ch == '\n')
            return State.QUOTED;
        
        // look for escaped characters
        if (ch == '\\')
            return State.QUOTED_ESCAPE;
        
        // DQUOTE ends quoted string and return to parsing atoms
        if (ch == '\"') {
            save_string_parameter();
            
            return State.START_PARAM;
        }
        
        append_to_string(ch);
        
        return State.QUOTED;
    }
    
    private uint on_quoted_escape_char(uint state, uint event, void *user) {
        unichar ch = *((unichar *) user);
        
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
        unichar ch = *((unichar *) user);
        
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
        unichar ch = *((unichar *) user);
        
        // anything but a space indicates the atom is continuing, therefore return to prior state
        if (ch != ' ')
            return on_partial_body_atom_char(State.PARTIAL_BODY_ATOM, event, user);
        
        save_string_parameter();
        
        return State.START_PARAM;
    }
    
    private uint on_literal_char(uint state, uint event, void *user) {
        unichar ch = *((unichar *) user);
        
        // if close-bracket, end of literal length field -- next event must be EOL
        if (ch == '}') {
            // empty literal treated as garbage
            if (is_current_string_empty())
                return State.FAILED;
            
            literal_length_remaining = (size_t) long.parse(current_string.str);
            if (literal_length_remaining < 0) {
                warning("Negative literal data length %lu", literal_length_remaining);
                
                return State.FAILED;
            }
            
            clear_string_parameter();
            
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
    
    private uint on_eos() {
        debug("[%s] EOS", to_string());
        
        // always signal as closed and notify subscribers
        closed_semaphore.blind_notify();
        eos();
        
        return State.CLOSED;
    }
    
    private uint on_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        
        debug("[%s] input error: %s", to_string(), err.message);
        
        // only Cancellable allowed is internal used to notify when closed; all other errors should
        // be reported
        if (!(err is IOError.CANCELLED))
            receive_failure(err);
        
        // always signal as closed and notify
        closed_semaphore.blind_notify();
        eos();
        
        return State.CLOSED;
    }
    
    private uint on_bad_transition(uint state, uint event, void *user) {
        warning("Bad event %s at state %s", event_to_string(event), state_to_string(state));
        
        return State.FAILED;
    }
    
    public string to_string() {
        return "%s/%s".printf(fsm.to_string(), get_mode().to_string());
    }
}

