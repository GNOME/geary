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

    /** The status response for the command, once it has been received. */
    public StatusResponse? status { get; private set; default = null; }

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

    private bool timed_out = false;
    private bool cancelled = false;

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
        this.tag = Tag.get_unassigned();
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
     * Can only be called on a Command that holds an unassigned tag,
     * and hence this can only be called once at most. Throws an error
     * if already assigned or if the supplied tag is unassigned.
     */
    internal void assign_tag(Tag new_tag) throws ImapError {
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
                    yield literal.serialize_data(ser, cancellable);
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
     * Cancels this command's execution.
     *
     * When this method is called, all locks will be released,
     * including {@link wait_until_complete}, which will then throw a
     * `GLib.IOError.CANCELLED` error.
     */
    internal virtual void cancel_command() {
        cancel_send();
        this.cancelled = true;
        this.response_timer.reset();
        this.complete_lock.blind_notify();
    }

    /**
     * Yields until the command has been completed or cancelled.
     *
     * Throws an error if the command or the cancellable argument is
     * cancelled, if the command timed out, or if the command's
     * response was bad.
     */
    public async void wait_until_complete(GLib.Cancellable cancellable)
        throws GLib.Error {
        yield this.complete_lock.wait_async(cancellable);

        if (this.cancelled) {
            throw new GLib.IOError.CANCELLED(
                "%s: Command was cancelled", to_brief_string()
            );
        }

        if (this.timed_out) {
            throw new ImapError.TIMED_OUT(
                "%s: Command timed out", to_brief_string()
            );
        }

        // Since this is part of the public API, perform a strict
        // check on the status code.
        check_status(true);
    }

    public virtual string to_string() {
        string args = this.args.to_string();
        return (Geary.String.is_empty(args))
            ? "%s %s".printf(this.tag.to_string(), this.name)
            : "%s %s %s".printf(this.tag.to_string(), this.name, args);
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
            cancel_send();
            throw new ImapError.SERVER_ERROR(
                "%s: Duplicate status response received: %s",
                to_brief_string(),
                status.to_string()
            );
        }

        this.status = new_status;
        this.response_timer.reset();
        this.complete_lock.blind_notify();
        cancel_send();
        // Since this gets called by the client connection only check
        // for an expected server response, good or bad
        check_status(false);
    }

    /**
     * Called when tagged server data is received for this command.
     */
    internal virtual void data_received(ServerData data)
        throws ImapError {
        if (this.status != null) {
            cancel_send();
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
            cancel_send();
            throw new ImapError.SERVER_ERROR(
                "%s: Continuation requested when command already complete",
                to_brief_string()
            );
        }

        if (this.literal_spinlock == null) {
            cancel_send();
            throw new ImapError.SERVER_ERROR(
                "%s: Continuation requested but no literals available",
                to_brief_string()
            );
        }

        this.response_timer.start();
        this.literal_spinlock.blind_notify();
    }

    /**
     * Cancels any existing serialisation in progress.
     *
     * When this method is called, any non I/O related process
     * blocking the blocking {@link send} must be cancelled.
     */
    protected virtual void cancel_send() {
        if (this.literal_cancellable != null) {
            this.literal_cancellable.cancel();
        }
    }

    private void check_status(bool require_okay) throws ImapError {
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

        // XXX should we be distinguishing between NO and BAD
        // responses here?
        if (require_okay && this.status.status != Status.OK) {
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
        this.timed_out = true;
        cancel_command();
        response_timed_out();
    }

}
