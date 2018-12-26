/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockAccount : Account, MockObject {


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


    public class MockClientService : ClientService {

        public MockClientService(AccountInformation account,
                                 ServiceInformation configuration,
                                 Endpoint remote) {
            base(account, configuration, remote);
        }

        public override async void start(GLib.Cancellable? cancellable = null)
            throws GLib.Error {
            throw new EngineError.UNSUPPORTED("Mock method");
        }

        public override async void stop(GLib.Cancellable? cancellable = null)
            throws GLib.Error {
            throw new EngineError.UNSUPPORTED("Mock method");
        }

    }


    public override bool is_online { get; protected set; default = false; }

    public override ClientService incoming {
        get { return this.incoming; }
    }
    private ClientService _incoming;

    public override ClientService outgoing {
        get { return this._outgoing; }
    }
    private ClientService _outgoing;

    protected Gee.Queue<ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ExpectedCall>();
    }


    public MockAccount(AccountInformation config) {
        base(config);
        this._incoming = new MockClientService(
            config,
            config.incoming,
            new Endpoint(config.incoming.host, config.incoming.port, 0, 0)
        );
        this._outgoing = new MockClientService(
            config,
            config.outgoing,
            new Endpoint(config.outgoing.host, config.outgoing.port, 0, 0)
        );
    }

    public override async void open_async(Cancellable? cancellable = null) throws Error {
        void_call("open_async", { cancellable });
    }

    public override async void close_async(Cancellable? cancellable = null) throws Error {
        void_call("close_async", { cancellable });
    }

    public override bool is_open() {
        try {
            return boolean_call("is_open", {}, false);
        } catch (Error err) {
            return false;
        }
    }

    public override async void rebuild_async(Cancellable? cancellable = null) throws Error {
        void_call("rebuild_async", { cancellable });
    }

    public override Gee.Collection<Folder> list_matching_folders(FolderPath? parent) {
        try {
            return object_call<Gee.Collection<Folder>>(
                "get_containing_folders_async", {parent}, Gee.List.empty<Folder>()
            );
        } catch (GLib.Error err) {
            return Gee.Collection.empty<Folder>();
        }
    }

    public override Gee.Collection<Folder> list_folders() throws Error {
        return object_call<Gee.Collection<Folder>>(
            "list_folders", {}, Gee.List.empty<Folder>()
        );
    }

    public override Geary.ContactStore get_contact_store() {
        return new MockContactStore();
    }

    public override async bool folder_exists_async(FolderPath path,
                                                   Cancellable? cancellable = null)
        throws Error {
        return boolean_call("folder_exists_async", {path, cancellable}, false);
    }

    public override async Folder fetch_folder_async(FolderPath path,
                                                    Cancellable? cancellable = null)
    throws Error {
        return object_or_throw_call<Folder>(
            "fetch_folder_async",
            {path, cancellable},
            new EngineError.NOT_FOUND("Mock call")
        );
    }

    public override Folder? get_special_folder(SpecialFolderType special)
        throws Error {
        return object_call<Folder?>(
            "get_special_folder", {box_arg(special)}, null
        );
    }

    public override async Folder get_required_special_folder_async(SpecialFolderType special,
                                                                   Cancellable? cancellable = null)
    throws Error {
        return object_or_throw_call<Folder>(
            "get_required_special_folder_async",
            {box_arg(special), cancellable},
            new EngineError.NOT_FOUND("Mock call")
        );
    }

    public override async void send_email_async(ComposedEmail composed,
                                                Cancellable? cancellable = null)
        throws Error {
        void_call("send_email_async", {composed, cancellable});
    }

    public override async Gee.MultiMap<Email,FolderPath?>?
        local_search_message_id_async(RFC822.MessageID message_id,
                                      Email.Field requested_fields,
                                      bool partial_ok,
                                      Gee.Collection<FolderPath?>? folder_blacklist,
                                      EmailFlags? flag_blacklist,
                                      Cancellable? cancellable = null)
        throws Error {
        return object_call<Gee.MultiMap<Email,FolderPath?>?>(
            "local_search_message_id_async",
            {
                message_id,
                box_arg(requested_fields),
                box_arg(partial_ok),
                folder_blacklist,
                flag_blacklist,
                cancellable
            },
            null
        );
    }

    public override async Email local_fetch_email_async(EmailIdentifier email_id,
                                                        Email.Field required_fields,
                                                        Cancellable? cancellable = null)
        throws Error {
        return object_or_throw_call<Email>(
            "local_fetch_email_async",
            {email_id, box_arg(required_fields), cancellable},
            new EngineError.NOT_FOUND("Mock call")
        );
    }

    public override SearchQuery open_search(string query, SearchQuery.Strategy strategy) {
        return new MockSearchQuery();
    }

    public override async Gee.Collection<EmailIdentifier>?
        local_search_async(SearchQuery query,
                           int limit = 100,
                           int offset = 0,
                           Gee.Collection<FolderPath?>? folder_blacklist = null,
                           Gee.Collection<EmailIdentifier>? search_ids = null,
                           Cancellable? cancellable = null)
        throws Error {
        return object_call<Gee.Collection<EmailIdentifier>?>(
            "local_search_async",
            {
                query,
                box_arg(limit),
                box_arg(offset),
                folder_blacklist,
                search_ids,
                cancellable
            },
            null
        );
    }

    public override async Gee.Set<string>?
        get_search_matches_async(SearchQuery query,
                                 Gee.Collection<EmailIdentifier> ids,
                                 Cancellable? cancellable = null)
        throws Error {
        return object_call<Gee.Set<string>?>(
            "get_search_matches_async", {query, ids, cancellable}, null
        );
    }

    public override async Gee.MultiMap<EmailIdentifier, FolderPath>?
        get_containing_folders_async(Gee.Collection<EmailIdentifier> ids,
                                     Cancellable? cancellable) throws Error {
        return object_call<Gee.MultiMap<EmailIdentifier, FolderPath>?>(
            "get_containing_folders_async", {ids, cancellable}, null
        );
    }

    internal override void set_endpoint(ClientService service,
                                        Endpoint endpoint) {
        try {
            void_call("set_endpoint", {service, endpoint});
        } catch (GLib.Error err) {
            // oh well
        }
    }

}
