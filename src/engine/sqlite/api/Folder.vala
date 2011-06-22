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
    private ImapMessageLocationPropertiesTable imap_location_table;
    private string name;
    
    internal Folder(MailDatabase db, FolderRow folder_row) throws Error {
        this.db = db;
        this.folder_row = folder_row;
        
        name = folder_row.name;
        
        message_table = db.get_message_table();
        location_table = db.get_message_location_table();
        imap_location_table = db.get_imap_message_location_table();
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
    
    public async void create_email_async(Geary.Email email, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        int64 message_id = yield message_table.create_async(
            new MessageRow.from_email(message_table, email),
            cancellable);
        
        Geary.Imap.EmailLocation location = (Geary.Imap.EmailLocation) email.location;
        
        MessageLocationRow location_row = new MessageLocationRow(location_table, Row.INVALID_ID,
            message_id, folder_row.id, location.position);
        int64 location_id = yield location_table.create_async(location_row, cancellable);
        
        ImapMessageLocationPropertiesRow imap_location_row = new ImapMessageLocationPropertiesRow(
            imap_location_table, Row.INVALID_ID, location_id, location.uid);
        yield imap_location_table.create_async(imap_location_row, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_async(int low, int count, Geary.Email.Field fields,
        Cancellable? cancellable) throws Error {
        assert(low >= 1);
        assert(count >= 1);
        
        // low is zero-based in the database.
        Gee.List<MessageLocationRow>? list = yield location_table.list_async(folder_row.id, low,
            count, cancellable);
        
        return yield list_email(list, fields, cancellable);
    }
    
    public async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field fields, Cancellable? cancellable = null) throws Error {
        Gee.List<MessageLocationRow>? list = yield location_table.list_sparse_async(folder_row.id,
            by_position, cancellable);
        
        return yield list_email(list, fields, cancellable);
    }
    
    private async Gee.List<Geary.Email>? list_email(Gee.List<MessageLocationRow>? list,
        Geary.Email.Field fields, Cancellable? cancellable) throws Error {
        if (list == null || list.size == 0)
            return null;
        
        Gee.List<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        foreach (MessageLocationRow location_row in list) {
            ImapMessageLocationPropertiesRow? imap_location_row = yield imap_location_table.fetch_async(
                location_row.id, cancellable);
            assert(imap_location_row != null);
            
            MessageRow? message_row = yield message_table.fetch_async(location_row.message_id,
                fields, cancellable);
            assert(message_row != null);
            
            emails.add(message_row.to_email(new Geary.Imap.EmailLocation(location_row.position,
                imap_location_row.uid)));
        }
        
        return (emails.size > 0) ? emails : null;
    }
    
    public async Geary.Email fetch_email_async(int position, Geary.Email.Field fields,
        Cancellable? cancellable = null) throws Error {
        assert(position >= 1);
        
        // num is zero-based in the database.
        MessageLocationRow? location_row = yield location_table.fetch_async(folder_row.id, position,
            cancellable);
        if (location_row == null)
            throw new EngineError.NOT_FOUND("No message at position %d in folder %s", position, name);
        
        assert(location_row.position == position);
        
        ImapMessageLocationPropertiesRow? imap_location_row = yield imap_location_table.fetch_async(
            location_row.id, cancellable);
        if (imap_location_row == null) {
            throw new EngineError.NOT_FOUND("No IMAP location properties at position %d in %s",
                position, name);
        }
        
        assert(imap_location_row.location_id == location_row.id);
        
        MessageRow? message_row = yield message_table.fetch_async(location_row.message_id, fields,
            cancellable);
        if (message_row == null)
            throw new EngineError.NOT_FOUND("No message at position %d in folder %s", position, name);
        
        return message_row.to_email(new Geary.Imap.EmailLocation(location_row.position,
            imap_location_row.uid));
    }
}

