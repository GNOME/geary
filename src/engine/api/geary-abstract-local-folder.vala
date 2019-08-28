/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Handles open/close for local folders.
 */
public abstract class Geary.AbstractLocalFolder : Geary.Folder {
    private ProgressMonitor _opening_monitor = new Geary.ReentrantProgressMonitor(Geary.ProgressType.ACTIVITY);
    public override Geary.ProgressMonitor opening_monitor { get { return _opening_monitor; } }

    private int open_count = 0;
    private Nonblocking.Semaphore closed_semaphore = new Nonblocking.Semaphore();

    protected AbstractLocalFolder() {
        // Notify now to ensure that wait_for_close_async does not
        // block if never opened.
        this.closed_semaphore.blind_notify();
    }

    public override Geary.Folder.OpenState get_open_state() {
        return open_count > 0 ? Geary.Folder.OpenState.LOCAL : Geary.Folder.OpenState.CLOSED;
    }

    protected void check_open() throws EngineError {
        if (open_count == 0)
            throw new EngineError.OPEN_REQUIRED("%s not open", to_string());
    }

    protected bool is_open() {
        return open_count > 0;
    }

    public override async bool open_async(Geary.Folder.OpenFlags open_flags, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0)
            return false;

        closed_semaphore.reset();

        notify_opened(Geary.Folder.OpenState.LOCAL, properties.email_total);

        return true;
    }

    public override async bool close_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || --open_count > 0)
            return false;

        closed_semaphore.blind_notify();

        notify_closed(Geary.Folder.CloseReason.LOCAL_CLOSE);
        notify_closed(Geary.Folder.CloseReason.FOLDER_CLOSED);

        return false;
    }

    public override async void wait_for_close_async(Cancellable? cancellable = null) throws Error {
        yield closed_semaphore.wait_async(cancellable);
    }

    public override async void synchronise_remote(GLib.Cancellable? cancellable)
        throws GLib.Error {
        // No-op
    }

}
