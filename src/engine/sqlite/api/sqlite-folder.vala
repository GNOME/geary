/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// TODO: This class currently deals with generic email storage as well as IMAP-specific issues; in
// the future, to support other email services, will need to break this up.

public class Geary.Sqlite.Folder : Geary.AbstractFolder, Geary.LocalFolder {
    private MailDatabase db;
    private FolderRow folder_row;
    private MessageTable message_table;
    private MessageLocationTable location_table;
    private ImapMessageLocationPropertiesTable imap_location_table;
    private Geary.FolderPath path;
    private bool opened = false;
    
    internal Folder(MailDatabase db, FolderRow folder_row, Geary.FolderPath path) throws Error {
        this.db = db;
        this.folder_row = folder_row;
        this.path = path;
        
        message_table = db.get_message_table();
        location_table = db.get_message_location_table();
        imap_location_table = db.get_imap_message_location_table();
    }
    
    private void check_open() throws Error {
        if (!opened)
            throw new EngineError.OPEN_REQUIRED("%s not open", to_string());
    }
    
    public override Geary.FolderPath get_path() {
        return path;
    }
    
    public override Geary.FolderProperties? get_properties() {
        return null;
    }
    
    public override async void open_async(bool readonly, Cancellable? cancellable = null) throws Error {
        if (opened)
            throw new EngineError.ALREADY_OPEN("%s already open", to_string());
        
        opened = true;
        notify_opened();
    }
    
    public override async void close_async(Cancellable? cancellable = null) throws Error {
        if (!opened)
            return;
        
        opened = false;
        notify_closed(CloseReason.FOLDER_CLOSED);
    }
    
    public override async int get_email_count(Cancellable? cancellable = null) throws Error {
        check_open();
        
        // TODO
        return 0;
    }
    
    public override async void create_email_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        Geary.Imap.EmailLocation location = (Geary.Imap.EmailLocation) email.location;
        
        // See if it already exists; first by UID (which is only guaranteed to be unique in a folder,
        // not account-wide)
        int64 message_id;
        if (yield imap_location_table.search_uid_in_folder(location.uid, folder_row.id, out message_id,
            cancellable)) {
            throw new EngineError.ALREADY_EXISTS("Email with UID %s already exists in %s",
                location.uid.to_string(), to_string());
        }
        
        // TODO: The following steps should be atomic
        message_id = yield message_table.create_async(
            new MessageRow.from_email(message_table, email),
            cancellable);
        
        MessageLocationRow location_row = new MessageLocationRow(location_table, Row.INVALID_ID,
            message_id, folder_row.id, location.position);
        int64 location_id = yield location_table.create_async(location_row, cancellable);
        
        ImapMessageLocationPropertiesRow imap_location_row = new ImapMessageLocationPropertiesRow(
            imap_location_table, Row.INVALID_ID, location_id, location.uid);
        yield imap_location_table.create_async(imap_location_row, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_async(int low, int count,
        Geary.Email.Field required_fields, Cancellable? cancellable) throws Error {
        assert(low >= 1);
        assert(count >= 1);
        
        check_open();
        
        Gee.List<MessageLocationRow>? list = yield location_table.list_async(folder_row.id, low,
            count, cancellable);
        
        return yield list_email(list, required_fields, cancellable);
    }
    
    public override async Gee.List<Geary.Email>? list_email_sparse_async(int[] by_position,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        check_open();
        
        Gee.List<MessageLocationRow>? list = yield location_table.list_sparse_async(folder_row.id,
            by_position, cancellable);
        
        return yield list_email(list, required_fields, cancellable);
    }
    
    private async Gee.List<Geary.Email>? list_email(Gee.List<MessageLocationRow>? list,
        Geary.Email.Field required_fields, Cancellable? cancellable) throws Error {
        check_open();
        
        if (list == null || list.size == 0)
            return null;
        
        // TODO: As this loop involves multiple database operations to form an email, might make
        // sense in the future to launch each async method separately, putting the final results
        // together when all the information is fetched
        Gee.List<Geary.Email> emails = new Gee.ArrayList<Geary.Email>();
        foreach (MessageLocationRow location_row in list) {
            // fetch the IMAP message location properties that are associated with the generic
            // message location
            ImapMessageLocationPropertiesRow? imap_location_row = yield imap_location_table.fetch_async(
                location_row.id, cancellable);
            assert(imap_location_row != null);
            
            // fetch the message itself
            MessageRow? message_row = yield message_table.fetch_async(location_row.message_id,
                required_fields, cancellable);
            assert(message_row != null);
            // only add to the list if the email contains all the required fields
            if (!message_row.fields.is_set(required_fields))
                continue;
            
            emails.add(message_row.to_email(new Geary.Imap.EmailLocation(location_row.position,
                imap_location_row.uid)));
        }
        
        return (emails.size > 0) ? emails : null;
    }
    
    public override async Geary.Email fetch_email_async(int position, Geary.Email.Field required_fields,
        Cancellable? cancellable = null) throws Error {
        assert(position >= 1);
        
        check_open();
        
        MessageLocationRow? location_row = yield location_table.fetch_async(folder_row.id, position,
            cancellable);
        if (location_row == null) {
            throw new EngineError.NOT_FOUND("No message at position %d in folder %s", position,
                to_string());
        }
        
        assert(location_row.position == position);
        
        ImapMessageLocationPropertiesRow? imap_location_row = yield imap_location_table.fetch_async(
            location_row.id, cancellable);
        if (imap_location_row == null) {
            throw new EngineError.NOT_FOUND("No IMAP location properties at position %d in %s",
                position, to_string());
        }
        
        assert(imap_location_row.location_id == location_row.id);
        
        MessageRow? message_row = yield message_table.fetch_async(location_row.message_id,
            required_fields, cancellable);
        if (message_row == null) {
            throw new EngineError.NOT_FOUND("No message at position %d in folder %s", position,
                to_string());
        }
        
        if (!message_row.fields.is_set(required_fields)) {
            throw new EngineError.INCOMPLETE_MESSAGE(
                "Message at position %d in folder %s only fulfills %Xh fields", position, to_string(),
                message_row.fields);
        }
        
        return message_row.to_email(new Geary.Imap.EmailLocation(location_row.position,
            imap_location_row.uid));
    }
    
    public async bool is_email_present_at(int position, out Geary.Email.Field available_fields,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        available_fields = Geary.Email.Field.NONE;
        
        MessageLocationRow? location_row = yield location_table.fetch_async(folder_row.id, position,
            cancellable);
        if (location_row == null)
            return false;
        
        return yield message_table.fetch_fields_async(location_row.message_id, out available_fields,
            cancellable);
    }
    
    public async bool is_email_associated_async(Geary.Email email, Cancellable? cancellable = null)
        throws Error {
        check_open();
        
        int64 message_id;
        return yield imap_location_table.search_uid_in_folder(
            ((Geary.Imap.EmailLocation) email.location).uid, folder_row.id, out message_id,
            cancellable);
    }
    
    public async void update_email_async(Geary.Email email, bool duplicate_okay,
        Cancellable? cancellable = null) throws Error {
        check_open();
        
        Geary.Imap.EmailLocation location = (Geary.Imap.EmailLocation) email.location;
        
        // See if the message can be identified in the folder (which both reveals association and
        // a message_id that can be used for a merge; note that this works without a Message-ID)
        int64 message_id;
        bool associated = yield imap_location_table.search_uid_in_folder(location.uid, folder_row.id,
            out message_id, cancellable);
        
        // If working around the lack of a Message-ID and not associated with this folder, treat
        // this operation as a create; otherwise, since a folder-association is determined, do
        // a merge
        if (email.message_id == null) {
            if (!associated) {
                if (!duplicate_okay)
                    throw new EngineError.INCOMPLETE_MESSAGE("No Message-ID");
                
                yield create_email_async(email, cancellable);
            } else {
                yield merge_email_async(message_id, email, cancellable);
            }
            
            return;
        }
        
        // If not associated, find message with matching Message-ID
        if (!associated) {
            Gee.List<int64?>? list = yield message_table.search_message_id_async(email.message_id,
                cancellable);
            
            // If none found, this operation is a create
            if (list == null || list.size == 0) {
                yield create_email_async(email, cancellable);
                
                return;
            }
            
            // Too many found turns this operation into a create
            if (list.size != 1) {
                yield create_email_async(email, cancellable);
                
                return;
            }
            
            message_id = list[0];
        }
        
        // Found a message.  If not associated with this folder, associate now.
        // TODO: Need to lock the database during this operation, as these steps should be atomic.
        if (!associated) {
            // see if an email exists at this position
            MessageLocationRow? location_row = yield location_table.fetch_async(folder_row.id,
                location.position);
            if (location_row != null) {
                throw new EngineError.ALREADY_EXISTS("Email already exists at position %d in %s",
                    email.location.position, to_string());
            }
            
            // insert email at supplied position
            location_row = new MessageLocationRow(location_table, Row.INVALID_ID, message_id,
                folder_row.id, location.position);
            int64 location_id = yield location_table.create_async(location_row, cancellable);
            
            // update position propeties
            ImapMessageLocationPropertiesRow imap_location_row = new ImapMessageLocationPropertiesRow(
                imap_location_table, Row.INVALID_ID, location_id, location.uid);
            yield imap_location_table.create_async(imap_location_row, cancellable);
        }
        
        // Merge any new information with the existing message in the local store
        yield merge_email_async(message_id, email, cancellable);
        
        // Done.
    }
    
    // TODO: The database should be locked around this method, as it should be atomic.
    // TODO: Merge email properties
    private async void merge_email_async(int64 message_id, Geary.Email email,
        Cancellable? cancellable = null) throws Error {
        assert(message_id != Row.INVALID_ID);
        
        // if nothing to merge, nothing to do
        if (email.fields == Geary.Email.Field.NONE)
            return;
        
        MessageRow? message_row = yield message_table.fetch_async(message_id, email.fields,
            cancellable);
        assert(message_row != null);
        
        message_row.merge_from_network(email);
        
        // possible nothing has changed or been added
        if (message_row.fields != Geary.Email.Field.NONE)
            yield message_table.merge_async(message_row, cancellable);
    }
}

