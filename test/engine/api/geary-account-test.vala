/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockAccount : Account {


    public class MockSearchQuery : SearchQuery {

        internal MockSearchQuery() {
            base("", SearchQuery.Strategy.EXACT);
        }

    }

    public class MockContactStore : ContactStore {

        internal MockContactStore() {
            
        }

        public override async void
            mark_contacts_async(Gee.Collection<Contact> contacts,
                                ContactFlags? to_add,
                                ContactFlags? to_remove) throws Error {
                throw new EngineError.UNSUPPORTED("Mock method");
            }
    }


    public MockAccount(string name, AccountInformation information) {
        base(name, information);
    }

    public override async void open_async(Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void close_async(Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override bool is_open() {
        return false;
    }

    public override async void rebuild_async(Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void start_outgoing_client()
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void start_incoming_client()
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override Gee.Collection<Geary.Folder> list_matching_folders(Geary.FolderPath? parent)
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override Gee.Collection<Geary.Folder> list_folders() throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override Geary.ContactStore get_contact_store() {
        return new MockContactStore();
    }

    public override async bool folder_exists_async(Geary.FolderPath path, Cancellable? cancellable = null)
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Geary.Folder fetch_folder_async(Geary.FolderPath path,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Geary.Folder get_required_special_folder_async(Geary.SpecialFolderType special,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Gee.MultiMap<Geary.Email, Geary.FolderPath?>? local_search_message_id_async(
        Geary.RFC822.MessageID message_id, Geary.Email.Field requested_fields, bool partial_ok,
        Gee.Collection<Geary.FolderPath?>? folder_blacklist, Geary.EmailFlags? flag_blacklist,
        Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Geary.Email local_fetch_email_async(Geary.EmailIdentifier email_id,
        Geary.Email.Field required_fields, Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override Geary.SearchQuery open_search(string query, Geary.SearchQuery.Strategy strategy) {
        return new MockSearchQuery();
    }

    public override async Gee.Collection<Geary.EmailIdentifier>? local_search_async(Geary.SearchQuery query,
        int limit = 100, int offset = 0, Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
        Gee.Collection<Geary.EmailIdentifier>? search_ids = null, Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Gee.Set<string>? get_search_matches_async(Geary.SearchQuery query,
        Gee.Collection<Geary.EmailIdentifier> ids, Cancellable? cancellable = null) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

    public override async Gee.MultiMap<EmailIdentifier, FolderPath>
        get_containing_folders_async(Gee.Collection<EmailIdentifier> ids,
                                     Cancellable? cancellable) throws Error {
        throw new EngineError.UNSUPPORTED("Mock method");
    }

}
