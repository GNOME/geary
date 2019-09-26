/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Provides a context for notification plugins.
 *
 * The context provides an interface for notification plugins to
 * interface with the Geary client application. Notification plugins
 * will be passed an instance of this class as the `context`
 * parameter.
 *
 * Plugins can connect to the "notify::count", the {@link
 * new_messages_arrived} or the {@link new_messages_retired} signals
 * and update their state as these change.
 */
public class Application.NotificationContext : Geary.BaseObject {


    /** Monitor hook for obtaining a contact store for an account. */
    internal delegate Application.ContactStore? GetContactStore(
        Geary.Account account
    );

    /** Monitor hook to determine if a folder should be notified about. */
    internal delegate bool ShouldNotifyNewMessages(Geary.Folder folder);


    private class MonitorInformation : Geary.BaseObject {
        public Geary.Folder folder;
        public GLib.Cancellable? cancellable = null;
        public int count = 0;
        public Gee.HashSet<Geary.EmailIdentifier> new_ids
            = new Gee.HashSet<Geary.EmailIdentifier>();

        public MonitorInformation(Geary.Folder folder, GLib.Cancellable? cancellable) {
            this.folder = folder;
            this.cancellable = cancellable;
        }
    }

    /** Current total new message count across all accounts and folders. */
    public int total_new_messages { get; private set; default = 0; }

    /**
     * Folder containing the recent new message received, if any.
     *
     * @see last_new_message
     */
    public Geary.Folder? last_new_message_folder {
        get; private set; default = null;
    }

    /**
     * Most recent new message received, if any.
     *
     * @see last_new_message_folder
     */
    public Geary.Email? last_new_message {
        get; private set; default = null;
    }

    /** Returns a store to lookup avatars for notifications. */
    public Application.AvatarStore avatars { get; private set; }


    private Geary.Email.Field required_fields { get; private set; default = FLAGS; }

    private Gee.Map<Geary.Folder, MonitorInformation> folder_information =
        new Gee.HashMap<Geary.Folder, MonitorInformation>();

    private unowned GetContactStore contact_store_delegate;
    private unowned ShouldNotifyNewMessages notify_delegate;


    /** Emitted when a new folder will be monitored. */
    public signal void folder_added(Geary.Folder folder);

    /** Emitted when a folder should no longer be monitored. */
    public signal void folder_removed(Geary.Folder folder);

    /** Emitted when new messages have been downloaded. */
    public signal void new_messages_arrived(Geary.Folder parent, int total, int added);

    /** Emitted when a folder has been cleared of new messages. */
    public signal void new_messages_retired(Geary.Folder parent, int total);

    /** Constructs a new context instance. */
    internal NotificationContext(AvatarStore avatars,
                                 GetContactStore contact_store_delegate,
                                 ShouldNotifyNewMessages notify_delegate) {
        this.avatars = avatars;
        this.contact_store_delegate = contact_store_delegate;
        this.notify_delegate = notify_delegate;
    }

    /** Determines if notifications should be made for a specific folder. */
    public bool should_notify_new_messages(Geary.Folder folder) {
        return this.notify_delegate(folder);
    }

    /** Returns a contact store to lookup contacts for notifications. */
    public Application.ContactStore? get_contact_store(Geary.Account account) {
        return this.contact_store_delegate(account);
    }

    /** Returns a read-only set the context's monitored folders. */
    public Gee.Collection<Geary.Folder> get_folders() {
        return this.folder_information.keys.read_only_view;
    }

    /** Returns the new message count for a specific folder. */
    public int get_new_message_count(Geary.Folder folder)
        throws Geary.EngineError.NOT_FOUND {
        MonitorInformation? info = folder_information.get(folder);
        if (info == null) {
            throw new Geary.EngineError.NOT_FOUND(
                "No such folder: %s", folder.path.to_string()
            );
        }
        return info.count;
    }

    /** Adds fields for loaded email required by a plugin. */
    public void add_required_fields(Geary.Email.Field fields) {
        this.required_fields |= fields;
    }

    /** Removes fields for loaded email no longer required by a plugin. */
    public void remove_required_fields(Geary.Email.Field fields) {
        this.required_fields ^= fields;
    }

    internal void add_folder(Geary.Folder folder, GLib.Cancellable? cancellable) {
        if (!this.folder_information.has_key(folder)) {
            folder.email_locally_appended.connect(on_email_locally_appended);
            folder.email_flags_changed.connect(on_email_flags_changed);
            folder.email_removed.connect(on_email_removed);

            this.folder_information.set(
                folder, new MonitorInformation(folder, cancellable)
            );

            folder_added(folder);
        }
    }

    internal void remove_folder(Geary.Folder folder) {
        if (folder_information.has_key(folder)) {
            folder.email_locally_appended.disconnect(on_email_locally_appended);
            folder.email_flags_changed.disconnect(on_email_flags_changed);
            folder.email_removed.disconnect(on_email_removed);

            this.total_new_messages -= this.folder_information.get(folder).count;

            this.folder_information.unset(folder);

            folder_removed(folder);
        }
    }

    internal void clear_folders() {
        // Get an array so the loop does not blow up when removing values.
        foreach (Geary.Folder monitored in this.folder_information.keys.to_array()) {
            remove_folder(monitored);
        }
    }

    internal bool are_any_new_messages(Geary.Folder folder,
                                     Gee.Collection<Geary.EmailIdentifier> ids)
        throws Geary.EngineError.NOT_FOUND {
        MonitorInformation? info = folder_information.get(folder);
        if (info == null) {
            throw new Geary.EngineError.NOT_FOUND(
                "No such folder: %s", folder.path.to_string()
            );
        }
        return Geary.traverse(ids).any((id) => info.new_ids.contains(id));
    }

    internal void clear_new_messages(Geary.Folder folder)
        throws Geary.EngineError.NOT_FOUND {
        MonitorInformation? info = folder_information.get(folder);
        if (info == null) {
            throw new Geary.EngineError.NOT_FOUND(
                "No such folder: %s", folder.path.to_string()
            );
        }

        info.new_ids.clear();
        last_new_message_folder = null;
        last_new_message = null;

        update_count(info, false, 0);
    }

    private void on_email_locally_appended(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        do_process_new_email.begin(folder, email_ids);
    }

    private void on_email_flags_changed(Geary.Folder folder,
        Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> ids) {
        retire_new_messages(folder, ids.keys);
    }

    private void on_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        retire_new_messages(folder, ids);
    }

    private async void do_process_new_email(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        MonitorInformation info = folder_information.get(folder);

        try {
            Gee.List<Geary.Email>? list = yield folder.list_email_by_sparse_id_async(email_ids,
                required_fields, Geary.Folder.ListFlags.NONE, info.cancellable);
            if (list == null || list.size == 0) {
                debug("Warning: %d new emails, but none could be listed", email_ids.size);

                return;
            }

            new_messages(info, list);

            debug("do_process_new_email: %d messages listed, %d unread in folder %s",
                list.size, info.count, folder.to_string());
        } catch (Error err) {
            debug("Unable to notify of new email: %s", err.message);
        }
    }

    private void new_messages(MonitorInformation info, Gee.Collection<Geary.Email> emails) {
        int appended_count = 0;
        foreach (Geary.Email email in emails) {
            if (!email.fields.fulfills(required_fields)) {
                debug("Warning: new message %s (%Xh) does not fulfill NewMessagesMonitor required fields of %Xh",
                    email.id.to_string(), email.fields, required_fields);
            }

            if (info.new_ids.contains(email.id))
                continue;

            if (!email.email_flags.is_unread())
                continue;

            last_new_message_folder = info.folder;
            last_new_message = email;

            info.new_ids.add(email.id);
            appended_count++;
        }

        update_count(info, true, appended_count);
    }

    private void retire_new_messages(Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> email_ids) {
        MonitorInformation info = folder_information.get(folder);

        int removed_count = 0;
        foreach (Geary.EmailIdentifier email_id in email_ids) {
            if (last_new_message != null && last_new_message.id.equal_to(email_id)) {
                last_new_message_folder = null;
                last_new_message = null;
            }

            if (info.new_ids.remove(email_id))
                removed_count++;
        }

        update_count(info, false, removed_count);
    }

    private void update_count(MonitorInformation info, bool arrived, int delta) {
        int new_size = info.new_ids.size;

        total_new_messages += new_size - info.count;
        info.count = new_size;

        if (arrived)
            new_messages_arrived(info.folder, info.count, delta);
        else
            new_messages_retired(info.folder, info.count);
    }

}
