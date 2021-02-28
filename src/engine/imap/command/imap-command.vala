/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP command (request).
 *
 * A Command is created by the caller and then submitted to a {@link ClientSession} or
 * {@link ClientConnection} for transmission to the server.  In response, one or more
 * {@link ServerResponse}s are returned, generally zero or more {@link ServerData}s followed by
 * a completion {@link StatusResponse}.  Untagged {@link StatusResponse}s may also be returned,
 * depending on the Command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6]]
 */
public abstract class Geary.Imap.Command : BaseObject {

    /**
     * Default timeout to wait for a server response for a command.
     */
    public const uint DEFAULT_RESPONSE_TIMEOUT_SEC = 30;


    /**
     * All IMAP commands are tagged with an identifier assigned by the client.
     *
     * Note that this is not immutable.  The general practice is to use an unassigned Tag
     * up until the {@link Command} is about to be transmitted, at which point a Tag is
     * assigned.  This allows for all commands to be issued in Tag "order".  This generally makes
     * tracing network traffic easier.
     *
     * @see Tag.get_unassigned
     * @see assign_tag
     */
    public Tag tag { get; private set; }

    /**
     * The name (or "verb") of this command.
     */
    public string name { get; private set; }

    /**
     * Number of seconds to wait for a server response to this command.
     */
    public uint response_timeout {
        get {
            return this._response_timeout;
        }
        set {
            this._response_timeout = value;
            this.response_timer.interval = value;
        }
    }
    private uint _response_timeout = DEFAULT_RESPONSE_TIMEOUT_SEC;

    /** The status response for the command, once it has been received. */
    public StatusResponse? status { get; private set; default = null; }

    /**
     * A guard to allow cancelling a command before it is sent.
     *
     * Since IMAP does not allow commands that have been sent to the
     * server to be cancelled, cancelling a command before sending it
     * is the last opportunity to prevent it from being executed. A
     * command queued to be sent will be sent as long as the
     * connection it was queued is open and this cancellable is null
     * or is not cancelled.
     *
     * @see Command.Command
     */
    public GLib.Cancellable? should_send { get; private set; default = null; }

    /**
     * The command's arguments as parameters.
     *
     * Subclassess may append arguments to this before {@link send} is
     * called, ideally from their constructors.
     */
    protected ListParameter args {
        get; private set; default = new RootParameters();
    }

    /**
     * Timer used to check for a response within {@link response_timeout}.
     */
    protected TimeoutManager response_timer { get; private set; }

    private Geary.Nonblocking.Semaphore complete_lock =
        new Geary.Nonblocking.Semaphore();

    private GLib.Error? cancelled_cause = null;

    private Geary.Nonblocking.Spinlock? literal_spinlock = null;
    private GLib.Cancellable? literal_cancellable = null;


    /**
     * Fired when the response timeout for this command has been reached.
     */
    public signal void response_timed_out();

    /**
     * Constructs a new command with an unassigned tag.
     *
     * Any arguments provided here will be converted to appropriate
     * string arguments. The given cancellable will be set as {@link
     * should_send}.
     *
     * @see Tag
     * @see should_send
     */
    protected Command(string name,
                      string[]? args,
                      GLib.Cancellable? should_send) {
        this.tag = Tag.get_unassigned();
        this.name = name;
        if (args != null) {
            foreach (string arg in args) {
                this.args.add(Parameter.get_for_string(arg));
            }
        }
        this.should_send = should_send;

        this.response_timer = new TimeoutManager.seconds(
            this._response_timeout, on_response_timeout
        );
    }

    public bool has_name(string name) {
        return Ascii.stri_equal(this.name, name);
    }

    /**
     * Assign a Tag to this command, if currently unassigned.
     *
     * Can only be called on a Command that holds an unassigned tag,
     * and hence this can only be called once at most. Throws an error
     * if already assigned or if the supplied tag is unassigned.
     */
    internal void assign_tag(Tag new_tag) throws ImapError {
        if (this.tag.is_assigned()) {
            throw new ImapError.NOT_SUPPORTED(
                "%s: Command tag is already assigned", to_brief_string()
            );
        }
        if (!new_tag.is_assigned()) {
            throw new ImapError.NOT_SUPPORTED(
                "%s: New tag is not assigned", to_brief_string()
            );
        }

        this.tag = new_tag;
    }

    /**
     * Serialises this command for transmission to the server.
     *
     * This will serialise its tag, name and arguments (if
     * any). Arguments are treated as strings and escaped as needed,
     * including being encoded as a literal. If any literals are
     * required, this method will yield until a command continuation
     * has been received, when it will resume the same process.
     */
    internal virtual async void send(Serializer ser,
                                     GLib.Cancellable cancellable)
        throws GLib.Error {
        this.response_timer.start();
        this.tag.serialize(ser, cancellable);
        ser.push_space(cancellable);
        ser.push_unquoted_string(this.name, cancellable);

        if (this.args != null) {
            foreach (Parameter arg in this.args.get_all()) {
                ser.push_space(cancellable);
                arg.serialize(ser, cancellable);

                LiteralParameter literal = arg as LiteralParameter;
                if (literal != null) {
                    // Need to manually flush after serialising the
                    // literal param, so it actually gets to the
                    // server
                    yield ser.flush_stream(cancellable);

                    if (this.literal_spinlock == null) {
                        // Lazily create these since they usually
                        // won't be needed
                        this.literal_cancellable = new GLib.Cancellable();
                        this.literal_spinlock = new Geary.Nonblocking.Spinlock(
                            this.literal_cancellable
                        );
                    }

                    // Will get notified via continuation_requested
                    // when server indicated the literal can be sent.
                    yield this.literal_spinlock.wait_async(cancellable);

                    // Buffer size is dependent on timeout, since we
                    // need to ensure we can send a full buffer before
                    // the timeout is up. v.92 56k baud modems have
                    // theoretical max upload of 48kbit/s and GSM 2G
                    // 40kbit/s, but typical is usually well below
                    // that, so assume a low end of 1kbyte/s. Hence
                    // buffer size needs to be less than or equal to
                    // (response_timeout * 1)k, rounded down to the
                    // nearest power of two.
                    uint buf_size = 1;
                    while (buf_size <= this.response_timeout) {
                        buf_size <<= 1;
                    }
                    buf_size >>= 1;

                    uint8[] buf = new uint8[buf_size * 1024];
                    GLib.InputStream data = literal.value.get_input_stream();
                    try {
                        while (true) {
                            size_t read;
                            yield data.read_all_async(
                                buf, Priority.DEFAULT, cancellable, out read
                            );
                            if (read <= 0) {
                                break;
                            }

                            buf.length = (int) read;
                            yield ser.push_literal_data(buf, cancellable);
                            this.response_timer.start();
                        }
                    } finally {
                        try {
                            yield data.close_async();
                        } catch (GLib.Error err) {
                            // Oh well
                        }
                    }
                }
            }
        }

        ser.push_eol(cancellable);
    }

    /**
     * Check for command-specific server responses after sending.
     *
     * This method is called after {@link send} and after {@link
     * ClientSession} has signalled the command has been sent, but
     * before the next command is processed. It allows command
     * implementations (e.g. {@link IdleCommand}) to asynchronously
     * wait for some kind of response from the server before allowing
     * additional commands to be sent.
     *
     * Most commands will not need to override this, and it by default
     * does nothing.
     */
    internal virtual async void send_wait(Serializer ser,
                                          GLib.Cancellable cancellable)
        throws GLib.Error {
        // Nothing to do by default
    }

    /**
     * Yields until the command has been completed or cancelled.
     *
     * Throws an error if the command or the cancellable argument is
     * cancelled, if the command timed out, or if the command's
     * response was bad.
     */
    public async void wait_until_complete(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.complete_lock.wait_async(cancellable);

        if (this.cancelled_cause != null) {
            throw this.cancelled_cause;
        }

        // If everything above is fine, but sending was cancelled, it
        // must have been cancelled after being sent. Throw an error
        // indicating this specifically.
        if (this.should_send != null &&
            this.should_send.is_cancelled()) {
            throw new GLib.IOError.CANCELLED(
                "Command was cancelled after sending: %s", to_brief_string()
            );
        }

        check_has_status();

        // Since this is part of the public API, perform a strict
        // check on the status code.
        if (this.status.status == Status.BAD) {
            throw new ImapError.SERVER_ERROR(
                "%s: Command failed: %s",
                to_brief_string(),
                this.status.to_string()
            );
        }
    }

    public virtual string to_string() {
        string args = this.args.to_string();
        return (Geary.String.is_empty(args))
            ? "%s %s".printf(this.tag.to_string(), this.name)
            : "%s %s %s".printf(this.tag.to_string(), this.name, args);
    }

    /**
     * Updates the commands response timer, if running.
     *
     * This will reset the command's response timer, preventing the
     * command from timing out for another {@link response_timeout}
     * seconds.
     */
    internal virtual void update_response_timer() {
        if (this.response_timer.is_running) {
            this.response_timer.start();
        }
    }

    /**
     * Called when a tagged status response is received for this command.
     *
     * This will update the command's {@link status} property, then
     * throw an error if it does not indicate a successful completion.
     */
    internal virtual void completed(StatusResponse new_status)
        throws ImapError {
        if (this.status != null) {
            stop_serialisation();
            throw new ImapError.SERVER_ERROR(
                "%s: Duplicate status response received: %s",
                to_brief_string(),
                status.to_string()
            );
        }

        this.status = new_status;
        this.response_timer.reset();
        this.complete_lock.blind_notify();
        stop_serialisation();

        check_has_status();
    }

    /**
     * Marks this command as being cancelled before being sent.
     *
     * When this method is called, all locks will be released,
     * including {@link wait_until_complete}, which will then throw a
     * `GLib.IOError.CANCELLED` error.
     */
    internal virtual void cancelled_before_send() {
        cancel(
            new GLib.IOError.CANCELLED(
                "Command was cancelled before sending: %s", to_brief_string()
            )
        );
    }

    /**
     * Cancels this command due to a network or server disconnect.
     *
     * When this method is called, all locks will be released,
     * including {@link wait_until_complete}, which will then throw a
     * `ImapError.NOT_CONNECTED` error.
     */
    internal virtual void disconnected(string reason) {
        cancel(new ImapError.NOT_CONNECTED("%s: %s", to_brief_string(), reason));
    }

    /**
     * Called when tagged server data is received for this command.
     */
    internal virtual void data_received(ServerData data)
        throws ImapError {
        if (this.status != null) {
            stop_serialisation();
            throw new ImapError.SERVER_ERROR(
                "%s: Server data received when command already complete: %s",
                to_brief_string(),
                data.to_string()
            );
        }

        this.response_timer.start();
    }

    /**
     * Called when a continuation was requested by the server.
     *
     * This will notify the command's literal spinlock so that if
     * {@link send} is waiting to send a literal, it will do so
     * now.
     */
    internal virtual void
        continuation_requested(ContinuationResponse continuation)
        throws ImapError {
        if (this.status != null) {
            stop_serialisation();
            throw new ImapError.SERVER_ERROR(
                "%s: Continuation requested when command already complete",
                to_brief_string()
            );
        }

        if (this.literal_spinlock == null) {
            stop_serialisation();
            throw new ImapError.SERVER_ERROR(
                "%s: Continuation requested but no literals available",
                to_brief_string()
            );
        }

        this.response_timer.start();
        this.literal_spinlock.blind_notify();
    }

    /** Returns the command tag and name for debugging. */
    internal string to_brief_string() {
        return "%s %s".printf(this.tag.to_string(), this.name);
    }

    /**
     * Stops any existing serialisation in progress.
     *
     * When this method is called, any non I/O related process
     * blocking the blocking {@link send} must be cancelled.
     */
    protected virtual void stop_serialisation() {
        if (this.literal_cancellable != null) {
            this.literal_cancellable.cancel();
        }
    }

    private void cancel(GLib.Error cause) {
        stop_serialisation();
        this.cancelled_cause = cause;
        this.response_timer.reset();
        this.complete_lock.blind_notify();
    }

    private void check_has_status() throws ImapError {
        if (this.status == null) {
            throw new ImapError.SERVER_ERROR(
                "%s: No command response was received",
                to_brief_string()
            );
        }

        if (!this.status.is_completion) {
            throw new ImapError.SERVER_ERROR(
                "%s: Command status response is not a completion: %s",
                to_brief_string(),
                this.status.to_string()
            );
        }
    }

    private void on_response_timeout() {
        cancel(
            new ImapError.TIMED_OUT("%s: Command timed out", to_brief_string())
        );
        response_timed_out();
    }

}
