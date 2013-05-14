/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Handles open/close for local folders.
 */
public abstract class Geary.AbstractLocalFolder : Geary.AbstractFolder {
    private int open_count = 0;
    
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
    
    public override async void wait_for_open_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0)
            throw new EngineError.OPEN_REQUIRED("%s not open".printf(get_display_name()));
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null)
        throws Error {
        if (open_count++ > 0)
            return;
        
        notify_opened(Geary.Folder.OpenState.LOCAL, get_properties().email_total);
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (open_count == 0 || --open_count > 0)
            return;
        
        notify_closed(Geary.Folder.CloseReason.LOCAL_CLOSE);
        notify_closed(Geary.Folder.CloseReason.FOLDER_CLOSED);
    }
}

