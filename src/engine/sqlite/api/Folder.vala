/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Folder : Object, Geary.Folder {
    private FolderRow row;
    
    public string name { get; protected set; }
    public Trillian is_readonly { get; protected set; }
    public Trillian supports_children { get; protected set; }
    public Trillian has_children { get; protected set; }
    public Trillian is_openable { get; protected set; }
    
    internal Folder(FolderRow row) throws Error {
        this.row = row;
        
        name = row.name;
        is_readonly = Trillian.UNKNOWN;
        supports_children = row.supports_children;
        has_children = Trillian.UNKNOWN;
        is_openable = row.is_openable;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        is_readonly = Trillian.TRUE;
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        is_readonly = Trillian.UNKNOWN;
    }
    
    public int get_message_count() throws Error {
        return 0;
    }
    
    public async Gee.List<Geary.EmailHeader>? read_async(int low, int count,
        Cancellable? cancellable = null) throws Error {
        return null;
    }
    
    public async Geary.Email fetch_async(Geary.EmailHeader header,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.OPEN_REQUIRED("Not implemented");
    }
}

