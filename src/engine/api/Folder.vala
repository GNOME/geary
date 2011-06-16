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
    
    public virtual void notify_opened() {
        opened();
    }
    
    public virtual void notify_closed(CloseReason reason) {
        closed(reason);
    }
    
    public virtual void notify_updated() {
        updated();
    }
    
    public abstract string get_name();
    
    public abstract Geary.FolderProperties? get_properties();
    
    public abstract async void open_async(bool readonly, Cancellable? cancellable = null) throws Error;
    
    public abstract async void close_async(Cancellable? cancellable = null) throws Error;
    
    public abstract int get_message_count() throws Error;
    
    public abstract async void create_email_async(Geary.Email email, Geary.EmailOrdering ordering,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * low is one-based.
     */
    public abstract async Gee.List<Geary.Email> list_email_async(int low, int count,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error;
    
    public abstract async Geary.Email fetch_email_async(int msg_num, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error;
}

