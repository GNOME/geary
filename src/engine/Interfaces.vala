/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public interface Geary.FolderDetail : Object {
    public abstract string name { get; protected set; }
}

public interface Geary.Account : Object {
    public abstract async Gee.Collection<FolderDetail> list(FolderDetail? parent,
        Cancellable? cancellable = null) throws Error;
    
    public abstract async Folder open(string folder, Cancellable? cancellable = null) throws Error;
}

public interface Geary.Folder : Object {
    public enum CloseReason {
        LOCAL_CLOSE,
        REMOTE_CLOSE,
        FOLDER_CLOSED
    }
    
    public abstract string name { get; protected set; }
    
    public abstract int count { get; protected set; }
    
    public abstract bool is_readonly { get; protected set; }
    
    public signal void closed(CloseReason reason);
    
    public abstract async Gee.List<Message>? read(int low, int count, Cancellable? cancellable = null)
        throws Error;
}

