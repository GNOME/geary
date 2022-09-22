/*
 * Copyright © 2017-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.Account : Geary.Account,
    ValaUnit.TestAssertions,
    ValaUnit.MockObject {


    protected Gee.Queue<ValaUnit.ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ValaUnit.ExpectedCall>();
    }


    public Account(Geary.AccountInformation config) {
        base(config,
             new ClientService(
                 config,
                 config.incoming,
                 new Geary.Endpoint(
                     new GLib.NetworkAddress(
                         config.incoming.host, config.incoming.port
                     ),
                     0, 0
                 )
             ),
             new ClientService(
                 config,
                 config.outgoing,
                 new Geary.Endpoint(
                     new GLib.NetworkAddress(
                         config.outgoing.host, config.outgoing.port
                     ),
                     0, 0
                 )
             )
        );
    }

    public override async void open_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        void_call("open_async", { cancellable });
    }

    public override async void close_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        void_call("close_async", { cancellable });
    }

    public override bool is_open() {
        try {
            return boolean_call("is_open", {}, false);
        } catch (GLib.Error err) {
            return false;
        }
    }

    public override void cancel_remote_update() {
        try {
            void_call("cancel_remote_update", {});
        } catch (GLib.Error err) {
        }
    }

    public override async void rebuild_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        void_call("rebuild_async", { cancellable });
    }

    public override Gee.Collection<Geary.Folder>
        list_matching_folders(Geary.FolderPath? parent) {
        try {
            return object_call<Gee.Collection<Geary.Folder>>(
                "get_containing_folders_async",
                {parent},
                Gee.List.empty<Geary.Folder>()
            );
        } catch (GLib.Error err) {
            return Gee.Collection.empty<Geary.Folder>();
        }
    }

    public override async Geary.Folder create_personal_folder(
        string name,
        Geary.Folder.SpecialUse use = NONE,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        return object_call<Folder>(
            "create_personal_folder",
            { box_arg(name), box_arg(use), cancellable },
            new Folder(null, null, null, use, null)
        );
    }

    /** {@inheritDoc} */
    public override void register_local_folder(Geary.Folder local)
        throws GLib.Error {
        void_call("register_local_folder", { local });
    }

    /** {@inheritDoc} */
    public override void deregister_local_folder(Geary.Folder local)
        throws GLib.Error {
        void_call("deregister_local_folder", { local });
    }

    public override Geary.EmailIdentifier to_email_identifier(GLib.Variant serialised)
        throws Geary.EngineError.BAD_PARAMETERS {
        try {
            return object_or_throw_call<Geary.EmailIdentifier>(
                "to_email_identifier",
                { box_arg(serialised) },
                new Geary.EngineError.BAD_PARAMETERS("Mock error")
            );
        } catch (Geary.EngineError.BAD_PARAMETERS err) {
            throw err;
        } catch (GLib.Error err) {
            return new EmailIdentifer(0);
        }
    }

    public override Geary.FolderPath to_folder_path(GLib.Variant serialised)
        throws Geary.EngineError.BAD_PARAMETERS {
        try {
            return object_or_throw_call<Geary.FolderPath>(
                "to_folder_path",
                { box_arg(serialised) },
                new Geary.EngineError.BAD_PARAMETERS("Mock error")
            );
        } catch (Geary.EngineError.BAD_PARAMETERS err) {
            throw err;
        } catch (GLib.Error err) {
            return new Geary.FolderRoot("#mock", false);
        }
    }

    public override Geary.Folder get_folder(Geary.FolderPath path)
        throws Geary.EngineError.NOT_FOUND {
        try {
            return object_or_throw_call<Folder>(
                "get_folder",
                { path },
                new Geary.EngineError.NOT_FOUND("Mock error")
            );
        } catch (Geary.EngineError.NOT_FOUND err) {
            throw err;
        } catch (GLib.Error err) {
            return new Folder(null, null, null, NONE, null);
        }
    }

    public override Gee.Collection<Geary.Folder> list_folders() {
        try {
            return object_call<Gee.Collection<Geary.Folder>>(
                "list_folders", {}, Gee.List.empty<Geary.Folder>()
            );
        } catch (GLib.Error err) {
            return Gee.List.empty<Geary.Folder>();
        }
    }

    public override Geary.Folder? get_special_folder(Geary.Folder.SpecialUse special) {
        try {
            return object_call<Geary.Folder?>(
                "get_special_folder", {box_arg(special)}, null
            );
        } catch (GLib.Error err) {
            return null;
        }
    }

    public override async Geary.Folder
        get_required_special_folder_async(Geary.Folder.SpecialUse special,
                                          GLib.Cancellable? cancellable = null)
    throws GLib.Error {
        return object_or_throw_call<Geary.Folder>(
            "get_required_special_folder_async",
            { box_arg(special), cancellable },
            new Geary.EngineError.NOT_FOUND("Mock call")
        );
    }

    public override async Gee.MultiMap<Geary.Email,Geary.FolderPath?>?
        local_search_message_id_async(Geary.RFC822.MessageID message_id,
                                      Geary.Email.Field requested_fields,
                                      bool partial_ok,
                                      Gee.Collection<Geary.FolderPath?>? folder_blacklist,
                                      Geary.EmailFlags? flag_blacklist,
                                      GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return object_call<Gee.MultiMap<Geary.Email,Geary.FolderPath?>?>(
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

    public override async Gee.List<Geary.Email> list_local_email_async(
        Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.Email.Field required_fields,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
        return object_or_throw_call<Gee.List<Geary.Email>>(
            "list_local_email_async",
            {ids, box_arg(required_fields), cancellable},
            new Geary.EngineError.NOT_FOUND("Mock call")
        );
    }

    public override async Geary.Email
        local_fetch_email_async(Geary.EmailIdentifier email_id,
                                Geary.Email.Field required_fields,
                                GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return object_or_throw_call<Geary.Email>(
            "local_fetch_email_async",
            {email_id, box_arg(required_fields), cancellable},
            new Geary.EngineError.NOT_FOUND("Mock call")
        );
    }

    public override Geary.SearchQuery new_search_query(
        Gee.List<Geary.SearchQuery.Term> expression,
        string text
    ) throws GLib.Error {
        return new SearchQuery(expression, text);
    }

    public override async Gee.Collection<Geary.EmailIdentifier>?
        local_search_async(Geary.SearchQuery query,
                           int limit = 100,
                           int offset = 0,
                           Gee.Collection<Geary.FolderPath?>? folder_blacklist = null,
                           Gee.Collection<Geary.EmailIdentifier>? search_ids = null,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return object_call<Gee.Collection<Geary.EmailIdentifier>?>(
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
        get_search_matches_async(Geary.SearchQuery query,
                                 Gee.Collection<Geary.EmailIdentifier> ids,
                                 GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return object_call<Gee.Set<string>?>(
            "get_search_matches_async", {query, ids, cancellable}, null
        );
    }

    public override async Gee.MultiMap<Geary.EmailIdentifier,Geary.FolderPath>?
        get_containing_folders_async(Gee.Collection<Geary.EmailIdentifier> ids,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        return object_call<Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>?>(
            "get_containing_folders_async", {ids, cancellable}, null
        );
    }

    public override async void cleanup_storage(GLib.Cancellable? cancellable) {
        try {
            void_call("cleanup_storage", {cancellable});
        } catch (GLib.Error err) {
            // fine
        }
    }

}
