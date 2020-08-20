/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Implementation of the notification plugin extension context.
 */
internal class Application.NotificationPluginContext :
    Geary.BaseObject, Plugin.NotificationContext {


    private const Geary.Email.Field REQUIRED_FIELDS  = FLAGS;


    private class ContactStoreImpl : Geary.BaseObject, Plugin.ContactStore {


        private Application.ContactStore backing;


        public ContactStoreImpl(Application.ContactStore backing) {
            this.backing = backing;
        }

        public async Gee.Collection<Contact> search(string query,
                                                    uint min_importance,
                                                    uint limit,
                                                    GLib.Cancellable? cancellable
        ) throws GLib.Error {
            return yield this.backing.search(
                query, min_importance, limit, cancellable
            );
        }

        public async Contact load(Geary.RFC822.MailboxAddress mailbox,
                                  GLib.Cancellable? cancellable
        ) throws GLib.Error {
            return yield this.backing.load(mailbox, cancellable);
        }

    }


    private class MonitorInformation : Geary.BaseObject {

        public Geary.Folder folder;
        public GLib.Cancellable? cancellable = null;
        public Gee.Set<Geary.EmailIdentifier> recent_ids =
            new Gee.HashSet<Geary.EmailIdentifier>();

        public MonitorInformation(Geary.Folder folder,
                                  GLib.Cancellable? cancellable) {
            this.folder = folder;
            this.cancellable = cancellable;
        }
    }

    public int total_new_messages { get { return this._total_new_messages; } }
    public int _total_new_messages = 0;

    private Gee.Map<Geary.Folder,MonitorInformation> folder_information =
        new Gee.HashMap<Geary.Folder,MonitorInformation>();

    private unowned Client application;
    private PluginManager.PluginGlobals globals;
    private PluginManager.PluginContext plugin;


    internal NotificationPluginContext(Client application,
                                       PluginManager.PluginGlobals globals,
                                       PluginManager.PluginContext plugin) {
        this.application = application;
        this.globals = globals;
        this.plugin = plugin;
    }

    public async Plugin.ContactStore get_contacts_for_folder(Plugin.Folder source)
        throws Plugin.Error.NOT_FOUND, Plugin.Error.PERMISSION_DENIED {
        Geary.Folder? folder = this.globals.folders.to_engine_folder(source);
        AccountContext? context = null;
        if (folder != null) {
            context = this.application.controller.get_context_for_account(
                folder.account.information
            );
        }
        if (context == null) {
            throw new Plugin.Error.NOT_FOUND(
                "No account for folder: %s", source.display_name
            );
        }
        return new ContactStoreImpl(context.contacts);
    }

    /**
     * Determines if notifications should be made for a specific folder.
     *
     * Notification plugins should call this to first before
     * displaying a "new mail" notification for mail in a specific
     * folder. It will return true for any monitored folder that is
     * not currently visible in the currently focused main window, if
     * any.
     */
    public bool should_notify_new_messages(Plugin.Folder target) {
        // Don't show notifications if the top of a monitored folder's
        // conversations are visible. That is, if there is a main
        // window, it's focused, the folder is selected, and the
        // conversation list is at the top.
        Geary.Folder? folder = this.globals.folders.to_engine_folder(target);
        MainWindow? window = this.application.last_active_main_window;
        return (
            folder != null &&
            this.folder_information.has_key(folder) && (
                window == null ||
                !window.has_toplevel_focus ||
                window.selected_folder != folder ||
                window.conversation_list_view.vadjustment.value > 0.0
            )
        );
    }

    /**
     * Returns the new message count for a specific folder.
     *
     * The context must have already been requested to monitor the
     * folder by a call to {@link start_monitoring_folder}.
     */
    public int get_new_message_count(Plugin.Folder target)
        throws Plugin.Error.NOT_FOUND {
        Geary.Folder? folder = this.globals.folders.to_engine_folder(target);
        MonitorInformation? info = null;
        if (folder != null) {
            info = folder_information.get(folder);
        }
        if (info == null) {
            throw new Plugin.Error.NOT_FOUND(
                "No such folder: %s", folder.path.to_string()
            );
        }
        return info.recent_ids.size;
    }

    /**
     * Starts monitoring a folder for new messages.
     *
     * Notification plugins should call this to start the context
     * recording new messages for a specific folder.
     */
    public void start_monitoring_folder(Plugin.Folder target) {
        Geary.Folder? folder = this.globals.folders.to_engine_folder(target);
        AccountContext? context =
            this.application.controller.get_context_for_account(
                folder.account.information
            );
        if (folder != null &&
            context != null &&
            !this.folder_information.has_key(folder)) {
            folder.email_locally_appended.connect(on_email_locally_appended);
            folder.email_flags_changed.connect(on_email_flags_changed);
            folder.email_removed.connect(on_email_removed);

            this.folder_information.set(
                folder, new MonitorInformation(folder, context.cancellable)
            );
        }
    }

    /** Stops monitoring a folder for new messages. */
    public void stop_monitoring_folder(Plugin.Folder target) {
        Geary.Folder? folder = this.globals.folders.to_engine_folder(target);
        if (folder != null) {
            remove_folder(folder);
        }
    }

    /** Determines if a folder is currently being monitored. */
    public bool is_monitoring_folder(Plugin.Folder target) {
        return this.folder_information.has_key(
            this.globals.folders.to_engine_folder(target)
        );
    }

    internal void destroy() {
        // Get an array so the loop does not blow up when removing values.
        foreach (Geary.Folder monitored in this.folder_information.keys.to_array()) {
            remove_folder(monitored);
        }
    }

    internal void clear_new_messages(Geary.Folder location,
                                     Gee.Set<Geary.App.Conversation>? visible) {
        MonitorInformation? info = this.folder_information.get(location);
        if (info != null) {
            foreach (Geary.App.Conversation conversation in visible) {
                if (Geary.traverse(
                        conversation.get_email_ids()
                    ).any((id) => info.recent_ids.contains(id))) {
                    Gee.Set<Geary.EmailIdentifier> old_ids = info.recent_ids;
                    info.recent_ids = new Gee.HashSet<Geary.EmailIdentifier>();
                    update_count(info, false, old_ids);
                    break;
                }
            }
        }
    }

    private void new_messages(MonitorInformation info,
                              Gee.Collection<Geary.Email> emails) {
        Gee.Collection<Geary.EmailIdentifier> added =
            new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (Geary.Email email in emails) {
            if (email.email_flags.is_unread() &&
                info.recent_ids.add(email.id)) {
                added.add(email.id);
            }
        }
        if (added.size > 0) {
            update_count(info, true, added);
        }
    }

    private void retire_new_messages(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids
    ) {
        MonitorInformation info = folder_information.get(folder);
        Gee.Collection<Geary.EmailIdentifier> removed =
            new Gee.HashSet<Geary.EmailIdentifier>();
        foreach (Geary.EmailIdentifier email_id in email_ids) {
            if (info.recent_ids.remove(email_id)) {
                removed.add(email_id);
            }
        }

        if (removed.size > 0) {
            update_count(info, false, removed);
        }
    }

    private void update_count(MonitorInformation info,
                              bool arrived,
                              Gee.Collection<Geary.EmailIdentifier> delta) {
        Plugin.Folder folder =
            this.globals.folders.to_plugin_folder(info.folder);
        AccountContext? context =
            this.application.controller.get_context_for_account(
                info.folder.account.information
            );
        if (arrived && context != null) {
            this._total_new_messages += delta.size;
            new_messages_arrived(
                folder,
                info.recent_ids.size,
                this.globals.email.to_plugin_ids(delta, context)
            );
        } else {
            this._total_new_messages -= delta.size;
            new_messages_retired(
                folder, info.recent_ids.size
            );
        }
        notify_property("total-new-messages");
    }

    private void remove_folder(Geary.Folder target) {
        MonitorInformation? info = this.folder_information.get(target);
        if (info != null) {
            target.email_locally_appended.disconnect(on_email_locally_appended);
            target.email_flags_changed.disconnect(on_email_flags_changed);
            target.email_removed.disconnect(on_email_removed);

            if (!info.recent_ids.is_empty) {
                this._total_new_messages -= info.recent_ids.size;
                notify_property("total-new-messages");
            }

            this.folder_information.unset(target);
        }

    }

    private async void do_process_new_email(
        Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids
    ) {
        MonitorInformation info = this.folder_information.get(folder);
        if (info != null) {
            Gee.List<Geary.Email>? list = null;
            try {
                list = yield folder.list_email_by_sparse_id_async(
                    email_ids,
                    REQUIRED_FIELDS,
                    NONE,
                    info.cancellable
                );
            } catch (GLib.Error err) {
                warning(
                    "Unable to list new email for notification: %s", err.message
                );
            }
            if (list != null && !list.is_empty) {
                new_messages(info, list);
            } else {
                warning(
                    "%d new emails, but none could be listed for notification",
                    email_ids.size
                );
            }
        }
    }

    private void on_email_locally_appended(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        do_process_new_email.begin(folder, email_ids);
    }

    private void on_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> ids) {
        retire_new_messages(folder, ids.keys);
    }

    private void on_email_removed(Geary.Folder folder,
                                  Gee.Collection<Geary.EmailIdentifier> ids) {
        retire_new_messages(folder, ids);
    }

}
