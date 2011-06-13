/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Folder : Object, Geary.Folder {
    private FolderRow row;
    private string name;
    private Trillian readonly;
    private Trillian supports_children;
    private Trillian children;
    private Trillian openable;
    
    internal Folder(FolderRow row) throws Error {
        this.row = row;
        
        name = row.name;
        readonly = Trillian.UNKNOWN;
        supports_children = row.supports_children;
        children = Trillian.UNKNOWN;
        openable = row.is_openable;
    }
    
    public string get_name() {
        return name;
    }
    
    public Trillian is_readonly() {
        return readonly;
    }
    
    public Trillian does_support_children() {
        return supports_children;
    }
    
    public Trillian has_children() {
        return children;
    }
    
    public Trillian is_openable() {
        return openable;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        this.readonly = Trillian.TRUE;
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
        this.readonly = Trillian.UNKNOWN;
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

