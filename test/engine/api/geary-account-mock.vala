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

        public override void became_reachable() {

        }

        public override void became_unreachable() {

        }

    }


    protected Gee.Queue<ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ExpectedCall>();
    }


    public MockAccount(AccountInformation config) {
        base(config,
             new MockClientService(
                 config,
                 config.incoming,
                 new Endpoint(
                     new GLib.NetworkAddress(
                         config.incoming.host, config.incoming.port
                     ),
                     0, 0
                 )
             ),
             new MockClientService(
                 config,
                 config.outgoing,
                 new Endpoint(
                     new GLib.NetworkAddress(
                         config.outgoing.host, config.outgoing.port
                     ),
                     0, 0
                 )
             )
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

    public override EmailIdentifier to_email_identifier(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
        try {
            return object_or_throw_call<EmailIdentifier>(
                "to_email_identifier",
                { box_arg(serialised) },
                new EngineError.BAD_PARAMETERS("Mock error")
            );
        } catch (EngineError.BAD_PARAMETERS err) {
            throw err;
        } catch (GLib.Error err) {
            return new MockEmailIdentifer(0);
        }
    }

    public override FolderPath to_folder_path(GLib.Variant serialised)
        throws EngineError.BAD_PARAMETERS {
        try {
            return object_or_throw_call<FolderPath>(
                "to_folder_path",
                { box_arg(serialised) },
                new EngineError.BAD_PARAMETERS("Mock error")
            );
        } catch (EngineError.BAD_PARAMETERS err) {
            throw err;
        } catch (GLib.Error err) {
            return new FolderRoot("#mock", false);
        }
    }

    public override Folder get_folder(FolderPath path)
        throws EngineError.NOT_FOUND {
        try {
            return object_or_throw_call<Folder>(
                "get_folder",
                { path },
                new EngineError.NOT_FOUND("Mock error")
            );
        } catch (EngineError.NOT_FOUND err) {
            throw err;
        } catch (GLib.Error err) {
            return new MockFolder(null, null, null, SpecialFolderType.NONE, null);
        }
    }

    public override Gee.Collection<Folder> list_folders() throws Error {
        return object_call<Gee.Collection<Folder>>(
            "list_folders", {}, Gee.List.empty<Folder>()
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

    public override async SearchQuery open_search(string query,
                                                  SearchQuery.Strategy strategy,
                                                  GLib.Cancellable? cancellable)
        throws GLib.Error {
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

}
