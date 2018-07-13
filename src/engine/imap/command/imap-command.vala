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
public class Geary.Imap.Command : BaseObject {

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

    /**
     * The command's arguments as parameters.
     *
     * Subclassess may append arguments to this before {@link
     * serialize} is called, ideally from the constructor.
     */
    protected ListParameter args {
        get; private set; default = new RootParameters();
    }

    /** The status response for the command, once it has been received. */
    public StatusResponse? status { get; private set; default = null; }

    private TimeoutManager response_timer;

    private Geary.Nonblocking.Semaphore complete_lock =
        new Geary.Nonblocking.Semaphore();

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
     * string arguments
     *
     * @see Tag
     */
    public Command(string name, string[]? args = null) {
        tag = Tag.get_unassigned();
        this.name = name;
        if (args != null) {
            foreach (string arg in args) {
                this.args.add(Parameter.get_for_string(arg));
            }
        }

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
     * Can only be called on a Command that holds an unassigned Tag.
     * Thus, this can only be called once at most, and zero times if
     * Command.assigned() was used to generate the Command.  Fires an
     * assertion if either of these cases is true, or if the supplied
     * Tag is unassigned.
     */
    public void assign_tag(Tag new_tag) throws ImapError {
        if (this.tag.is_assigned()) {
            throw new ImapError.SERVER_ERROR(
                "%s: Command tag is already assigned", to_brief_string()
            );
        }
        if (!new_tag.is_assigned()) {
            throw new ImapError.SERVER_ERROR(
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
    public virtual async void serialize(Serializer ser,
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
                    yield literal.serialize_data(ser, cancellable);
                }
            }
        }

        ser.push_eol(cancellable);
    }

    /**
     * Cancels any existing serialisation in progress.
     *
     * When this method is called, any non I/O related process
     * blocking the blocking {@link serialize} must be cancelled.
     */
    public virtual void cancel_serialization() {
        if (this.literal_cancellable != null) {
            this.literal_cancellable.cancel();
        }
    }

    /**
     * Yields until the command has been completed or cancelled.
     *
     * Throws an error if cancelled, or if the command's response was
     * bad.
     */
    public async void wait_until_complete(GLib.Cancellable cancellable)
        throws GLib.Error {
        yield this.complete_lock.wait_async(cancellable);
        check_status();
    }

    /**
     * Called when a tagged status response is received for this command.
     *
     * This will update the command's {@link status} property, then
     * throw an error it does not indicate a successful completion.
     */
    public virtual void completed(StatusResponse new_status)
        throws ImapError {
        if (this.status != null) {
            cancel_serialization();
            throw new ImapError.SERVER_ERROR(
                "%s: Duplicate status response received: %s",
                to_brief_string(),
                status.to_string()
            );
        }

        this.status = new_status;
        this.response_timer.reset();
        this.complete_lock.blind_notify();
        cancel_serialization();
        check_status();
    }

    /**
     * Called when tagged server data is received for this command.
     */
    public virtual void data_received(ServerData data)
        throws ImapError {
        if (this.status != null) {
            cancel_serialization();
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
     * {@link serialize} is waiting to send a literal, it will do so
     * now.
     */
    public virtual void
        continuation_requested(ContinuationResponse continuation)
        throws ImapError {
        if (this.status != null) {
            cancel_serialization();
            throw new ImapError.SERVER_ERROR(
                "%s: Continuation requested when command already complete",
                to_brief_string()
            );
        }

        if (this.literal_spinlock == null) {
            cancel_serialization();
            throw new ImapError.SERVER_ERROR(
                "%s: Continuation requested but no literals available",
                to_brief_string()
            );
        }

        this.response_timer.start();
        this.literal_spinlock.blind_notify();
    }

    public virtual string to_string() {
        string args = this.args.to_string();
        return (Geary.String.is_empty(args))
            ? "%s %s".printf(this.tag.to_string(), this.name)
            : "%s %s %s".printf(this.tag.to_string(), this.name, args);
    }

    private void check_status() throws ImapError {
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

        if (this.status.status != Status.OK) {
            throw new ImapError.SERVER_ERROR(
                "%s: Command failed: %s",
                to_brief_string(),
                this.status.to_string()
            );
        }
    }

    private string to_brief_string() {
        return "%s %s".printf(this.tag.to_string(), this.name);
    }

    private void on_response_timeout() {
        cancel_serialization();
        response_timed_out();
        this.complete_lock.blind_notify();
    }

}
