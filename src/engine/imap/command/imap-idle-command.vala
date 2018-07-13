/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The IMAP IDLE command.
 *
 * See [[http://tools.ietf.org/html/rfc2177]]
 */
public class Geary.Imap.IdleCommand : Command {

    public const string NAME = "IDLE";

    private const string DONE = "DONE";

    /** Determines if the server has acknowledged the IDLE request. */
    public bool idle_started { get; private set; default = false; }

    private bool serialised = false;
    private Geary.Nonblocking.Spinlock? exit_lock;
    private GLib.Cancellable? exit_cancellable = new GLib.Cancellable();


    public IdleCommand() {
        base(NAME);
        this.exit_lock = new Geary.Nonblocking.Spinlock(this.exit_cancellable);
    }

    public void exit_idle() {
        this.exit_lock.blind_notify();
    }

    /** Waits after serialisation has completed for {@link exit_idle}. */
    public override async void serialize(Serializer ser,
                                         GLib.Cancellable cancellable)
        throws GLib.Error {
        // Need to manually flush here since Dovecot doesn't like
        // getting IDLE in the same buffer as other commands.
        yield ser.flush_stream(cancellable);

        yield base.serialize(ser, cancellable);
        this.serialised = true;

        // Need to manually flush again since the connection will be
        // waiting this to complete before do so.
        yield ser.flush_stream(cancellable);

        // Now wait for exit_idle() to be called, the server to send a
        // status response, or everything to be cancelled.
        yield this.exit_lock.wait_async(cancellable);

        // If we aren't closed already, try sending DONE to exit IDLE
        if (this.status == null) {
            ser.push_unquoted_string(DONE);
            ser.push_eol(cancellable);
            yield ser.flush_stream(cancellable);
        }

        yield wait_until_complete(cancellable);
    }

    public override void cancel_serialization() {
        base.cancel_serialization();
        this.exit_cancellable.cancel();
    }

    public override void continuation_requested(ContinuationResponse response)
        throws ImapError {
        if (!this.serialised) {
            // Allow any args sent as literals to be processed
            // normally
            base.continuation_requested(response);
        } else {
            this.idle_started = true;
        }
    }

}
