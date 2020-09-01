/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The IMAP AUTHENTICATE command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.2.2]]
 */
public class Geary.Imap.AuthenticateCommand : Command {


    public const string NAME = "authenticate";

    private const string OAUTH2_METHOD = "xoauth2";
    private const string OAUTH2_RESP = "user=%s\001auth=Bearer %s\001\001";


    public string method { get; private set; }

    private LiteralParameter? response_literal = null;
    private bool serialised = false;
    private Geary.Nonblocking.Spinlock error_lock;
    private GLib.Cancellable error_cancellable = new GLib.Cancellable();


    private AuthenticateCommand(string method,
                                string data,
                                GLib.Cancellable? should_send) {
        base(NAME, { method, data }, should_send);
        this.method = method;
        this.error_lock = new Geary.Nonblocking.Spinlock(this.error_cancellable);
    }

    public AuthenticateCommand.oauth2(string user,
                                      string token,
                                      GLib.Cancellable? should_send) {
        string encoded_token = Base64.encode(
            OAUTH2_RESP.printf(user, token).data
        );
        this(OAUTH2_METHOD, encoded_token, should_send);
    }

    internal override async void send(Serializer ser,
                                      GLib.Cancellable cancellable)
        throws GLib.Error {
        yield base.send(ser, cancellable);
        this.serialised = true;

        // Need to manually flush here since the connection will be
        // waiting for all pending commands to complete before
        // flushing it itself
        yield ser.flush_stream(cancellable);
    }

    public override string to_string() {
        return "%s %s %s <token>".printf(
            tag.to_string(), this.name, this.method
        );
    }

    internal override async void send_wait(Serializer ser,
                                         GLib.Cancellable cancellable)
        throws GLib.Error {
        // Wait to either get a response or a continuation request
        yield this.error_lock.wait_async(cancellable);
        if (this.response_literal != null) {
            yield ser.push_literal_data(
                this.response_literal.value.get_uint8_array(), cancellable
            );
            ser.push_eol(cancellable);
            yield ser.flush_stream(cancellable);
        }

        yield wait_until_complete(cancellable);
    }

    internal override void completed(StatusResponse new_status)
        throws ImapError {
        this.error_lock.blind_notify();
        base.completed(new_status);
    }

    internal override void continuation_requested(ContinuationResponse response)
        throws ImapError {
        if (!this.serialised) {
            // Allow any args sent as literals to be processed
            // normally
            base.continuation_requested(response);
        } else {
            if (this.method != AuthenticateCommand.OAUTH2_METHOD ||
                this.response_literal != null) {
                stop_serialisation();
                throw new ImapError.INVALID(
                    "Unexpected AUTHENTICATE continuation request"
                );
            }

            // Continuation will be a Base64 encoded JSON blob and which
            // indicates a login failure. We don't really care about that
            // (do we?) though since once we acknowledge it with a
            // zero-length response the server will respond with an IMAP
            // error.
            this.response_literal = new LiteralParameter(
                Geary.Memory.EmptyBuffer.instance
            );
            // Notify serialisation to continue
            this.error_lock.blind_notify();
        }
    }

    protected override void stop_serialisation() {
        base.stop_serialisation();
        this.error_cancellable.cancel();
    }

}
