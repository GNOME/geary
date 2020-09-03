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
    private Geary.Nonblocking.Semaphore? exit_lock;
    private GLib.Cancellable? exit_cancellable = new GLib.Cancellable();


    public IdleCommand(GLib.Cancellable? should_send) {
        base(NAME, null, should_send);
        this.exit_lock = new Geary.Nonblocking.Semaphore(this.exit_cancellable);
    }

    /** Causes the idle command to exit, if currently executing. **/
    public void exit_idle() {
        this.exit_lock.blind_notify();
    }

    /** Waits after serialisation has completed for {@link exit_idle}. */
    internal override async void send(Serializer ser,
                                      GLib.Cancellable cancellable)
        throws GLib.Error {
        // Need to manually flush here since Dovecot doesn't like
        // getting IDLE in the same buffer as other commands.
        yield ser.flush_stream(cancellable);

        yield base.send(ser, cancellable);
        this.serialised = true;

        // Need to manually flush again since the connection will be
        // waiting for all pending commands to complete before
        // flushing it itself
        yield ser.flush_stream(cancellable);
    }

    internal override async void send_wait(Serializer ser,
                                           GLib.Cancellable cancellable)
        throws GLib.Error {
        // Wait for exit_idle() to be called, the server to send a
        // status response, or everything to be cancelled.
        yield this.exit_lock.wait_async(cancellable);

        // If we aren't done already, send DONE to exit IDLE. Restart
        // the response timer so we get a timeout if DONE is not
        // received in good time.
        if (this.status == null) {
            this.response_timer.start();
            ser.push_unquoted_string(DONE);
            ser.push_eol(cancellable);
            yield ser.flush_stream(cancellable);
        }

        // Wait until we get a status response so no other command is
        // sent between DONE and the status response.
        yield wait_until_complete(cancellable);
    }

    internal override void continuation_requested(ContinuationResponse response)
        throws ImapError {
        if (!this.serialised) {
            // Allow any args sent as literals to be processed
            // normally
            base.continuation_requested(response);
        } else {
            this.idle_started = true;
            // Reset the timer here since we know the command was
            // received fine.
            this.response_timer.reset();
        }
    }

    protected override void stop_serialisation() {
        base.stop_serialisation();
        this.exit_cancellable.cancel();
    }

}
