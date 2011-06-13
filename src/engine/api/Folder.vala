/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.Folder : Object {
    public enum CloseReason {
        LOCAL_CLOSE,
        REMOTE_CLOSE,
        FOLDER_CLOSED
    }
    
    public signal void opened();
    
    public signal void closed(CloseReason reason);
    
    public signal void updated();
    
    public abstract string get_name();
    
    // This is only for when a context has been selected
    public abstract Trillian is_readonly();
    
    public abstract Trillian does_support_children();
    
    public abstract Trillian has_children();
    
    public abstract Trillian is_openable();
    
    public abstract async void open_async(bool readonly, Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract int get_message_count() throws Error;
    
    public abstract async Gee.List<Geary.EmailHeader>? read_async(int low, int count,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Email fetch_async(Geary.EmailHeader header,
        Cancellable? cancellable = null) throws Error;
}

