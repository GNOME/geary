/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Folder : Object, Geary.Folder {
    private MailDatabase db;
    private FolderRow folder_row;
    private MessageTable message_table;
    private MessageLocationTable location_table;
    private string name;
    
    internal Folder(MailDatabase db, FolderRow folder_row) throws Error {
        this.db = db;
        this.folder_row = folder_row;
        
        name = folder_row.name;
        
        message_table = db.get_message_table();
        location_table = db.get_message_location_table();
    }
    
    public string get_name() {
        return name;
    }
    
    public Geary.FolderProperties? get_properties() {
        return null;
    }
    
    public async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
    }
    
    public async void close_async(Cancellable? cancellable = null) throws Error {
    }
    
    public int get_message_count() throws Error {
        return 0;
    }
    
    public async void create_email_async(Geary.Email email, Geary.EmailOrdering ordering, 
        Cancellable? cancellable = null) throws Error {
        int64 message_id = yield message_table.create_async(
            new MessageRow.from_email(message_table, email),
            cancellable);
        
        MessageLocationRow location_row = new MessageLocationRow(location_table, Row.INVALID_ID,
            message_id, folder_row.id, ordering.ordinal);
        yield location_table.create_async(location_row, cancellable);
    }
    
    public async Gee.List<Geary.Email> list_email_async(int low, int count, Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        assert(low >= 1);
        assert(count >= 1);
        
        // low is zero-based in the database.
        Gee.List<MessageLocationRow>? list = yield location_table.list_async(folder_row.id, low - 1,
            count, cancellable);
        if (list == null || list.size == 0)
            throw new EngineError.NOT_FOUND("No messages found at position %d in %s", low, name);
        
        Gee.List<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        int msg_num = 1;
        foreach (MessageLocationRow location_row in list) {
            MessageRow? message_row = yield message_table.fetch_async(location_row.message_id,
                fields, cancellable);
            assert(message_row != null);
            
            emails.add(message_row.to_email(msg_num++));
        }
        
        return (emails.size > 0) ? emails : null;
    }
    
    public async Geary.Email fetch_email_async(int num, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        assert(num >= 0);
        
        // num is zero-based in the database.
        MessageLocationRow? location_row = yield location_table.fetch_async(folder_row.id, num - 1,
            cancellable);
        if (location_row == null)
            throw new EngineError.NOT_FOUND("No message number %s in folder %s", num, name);
        
        MessageRow? message_row = yield message_table.fetch_async(location_row.message_id, fields,
            cancellable);
        if (message_row == null)
            throw new EngineError.NOT_FOUND("No message number %s in folde %s", num, name);
        
        return message_row.to_email(num);
    }
}

