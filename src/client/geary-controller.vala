/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Primary controller object for Geary.
public class GearyController {
    private class ListFoldersOperation : Geary.NonblockingBatchOperation {
        public Geary.Account account;
        public Geary.FolderPath path;
        
        public ListFoldersOperation(Geary.Account account, Geary.FolderPath path) {
            this.account = account;
            this.path = path;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            return yield account.list_folders_async(path, cancellable);
        }
    }
    
    private class FetchFolderOperation : Geary.NonblockingBatchOperation {
        public Geary.Account account;
        public Geary.FolderPath folder_path;
        
        public FetchFolderOperation(Geary.Account account, Geary.FolderPath folder_path) {
            this.account = account;
            this.folder_path = folder_path;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            return yield account.fetch_folder_async(folder_path);
        }
    }
    
    // Named actions.
    public const string ACTION_HELP = "GearyHelp";
    public const string ACTION_ABOUT = "GearyAbout";
    public const string ACTION_QUIT = "GearyQuit";
    public const string ACTION_NEW_MESSAGE = "GearyNewMessage";
    public const string ACTION_REPLY_TO_MESSAGE = "GearyReplyToMessage";
    public const string ACTION_REPLY_ALL_MESSAGE = "GearyReplyAllMessage";
    public const string ACTION_FORWARD_MESSAGE = "GearyForwardMessage";
    public const string ACTION_DELETE_MESSAGE = "GearyDeleteMessage";
    public const string ACTION_ZOOM_IN = "GearyZoomIn";
    public const string ACTION_ZOOM_OUT = "GearyZoomOut";
    public const string ACTION_ZOOM_NORMAL = "GearyZoomNormal";
    public const string ACTION_PREFERENCES = "GearyPreferences";
    public const string ACTION_MARK_AS_MENU = "GearyMarkAsMenuButton";
    public const string ACTION_MARK_AS_READ = "GearyMarkAsRead";
    public const string ACTION_MARK_AS_UNREAD = "GearyMarkAsUnread";
    public const string ACTION_MARK_AS_STARRED = "GearyMarkAsStarred";
    public const string ACTION_MARK_AS_UNSTARRED = "GearyMarkAsUnStarred";
    public const string ACTION_COPY_MENU = "GearyCopyMenuButton";
    public const string ACTION_MOVE_MENU = "GearyMoveMenuButton";

    private const int FETCH_EMAIL_CHUNK_COUNT = 50;
    
    private const string DELETE_MESSAGE_LABEL = _("_Delete");
    private const string DELETE_MESSAGE_TOOLTIP = null;
    private const string DELETE_MESSAGE_ICON_NAME = "user-trash-full";
    
    private const string ARCHIVE_MESSAGE_LABEL = _("_Archive");
    private const string ARCHIVE_MESSAGE_TOOLTIP = _("Archive the selected conversation");
    private const string ARCHIVE_MESSAGE_ICON_NAME = "archive-insert";
    
    public MainWindow main_window { get; private set; }
    public bool enable_load_more { get; set; default = true; }
    
    private Cancellable cancellable_folder = new Cancellable();
    private Cancellable cancellable_inbox = new Cancellable();
    private Cancellable cancellable_message = new Cancellable();
    private Geary.Folder? current_folder = null;
    private Geary.Folder? inbox_folder = null;
    private Geary.ConversationMonitor? current_conversations = null;
    private bool loading_local_only = true;
    private int busy_count = 0;
    private Gee.Set<Geary.Conversation> selected_conversations = new Gee.HashSet<Geary.Conversation>();
    private Geary.Conversation? last_deleted_conversation = null;
    private bool scan_in_progress = false;
    private int conversations_added_counter = 0;
    private Gee.LinkedList<ComposerWindow> composer_windows = new Gee.LinkedList<ComposerWindow>();
    private File? last_save_directory = null;

    private Geary.EngineAccount? account { get; private set; }
    
    public GearyController() {
        // Setup actions.
        GearyApplication.instance.actions.add_actions(create_actions(), this);
        GearyApplication.instance.ui_manager.insert_action_group(
            GearyApplication.instance.actions, 0);
        GearyApplication.instance.load_ui_file("accelerators.ui");
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
        
        // Listen for attempts to close the application.
        GearyApplication.instance.exiting.connect(on_application_exiting);
        
        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow();
        
        enable_message_buttons(false);

        // Connect to various UI signals.
        main_window.message_list_view.conversations_selected.connect(on_conversations_selected);
        main_window.message_list_view.load_more.connect(on_load_more);
        main_window.message_list_view.mark_conversation.connect(on_mark_conversation);
        main_window.folder_list.folder_selected.connect(on_folder_selected);
        main_window.folder_list.copy_conversation.connect(on_copy_conversation);
        main_window.folder_list.move_conversation.connect(on_move_conversation);
        main_window.main_toolbar.copy_folder_menu.folder_selected.connect(on_copy_conversation);
        main_window.main_toolbar.move_folder_menu.folder_selected.connect(on_move_conversation);
        main_window.message_viewer.link_selected.connect(on_link_selected);
        main_window.message_viewer.reply_to_message.connect(on_reply_to_message);
        main_window.message_viewer.reply_all_message.connect(on_reply_all_message);
        main_window.message_viewer.forward_message.connect(on_forward_message);
        main_window.message_viewer.mark_message.connect(on_message_viewer_mark_message);
        main_window.message_viewer.open_attachment.connect(on_open_attachment);
        main_window.message_viewer.save_attachments.connect(on_save_attachments);

        main_window.message_list_view.grab_focus();
        
        set_busy(false);
        
        main_window.show_all();
    }
    
    ~GearyController() {
        assert(account == null);
    }

    private void add_accelerator(string accelerator, string action) {
        // Parse the accelerator.
        uint key = 0;
        Gdk.ModifierType modifiers = 0;
        Gtk.accelerator_parse(accelerator, out key, out modifiers);
        if (key == 0) {
            debug("Failed to parse accelerator '%s'", accelerator);
            return;
        }

        // Connect the accelerator to the action.
        GearyApplication.instance.ui_manager.get_accel_group().connect(key, modifiers,
            Gtk.AccelFlags.VISIBLE, (group, obj, key, modifiers) => {
                GearyApplication.instance.actions.get_action(action).activate();
                return false;
            });
    }

    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] entries = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry prefs = { ACTION_PREFERENCES, Gtk.Stock.PREFERENCES, TRANSLATABLE, null,
            null, on_preferences };
        prefs.label = _("_Preferences");
        entries += prefs;

        Gtk.ActionEntry help = { ACTION_HELP, Gtk.Stock.HELP, TRANSLATABLE, "F1", null, on_help };
        help.label = _("_Help");
        entries += help;

        Gtk.ActionEntry about = { ACTION_ABOUT, Gtk.Stock.ABOUT, TRANSLATABLE, null, null, on_about };
        about.label = _("_About");
        entries += about;
        
        Gtk.ActionEntry quit = { ACTION_QUIT, Gtk.Stock.QUIT, TRANSLATABLE, "<Ctrl>Q", null, on_quit };
        quit.label = _("_Quit");
        entries += quit;
        
        Gtk.ActionEntry mark_menu = { ACTION_MARK_AS_MENU, null, TRANSLATABLE, null, null,
            on_show_mark_menu };
        mark_menu.label = _("_Mark as...");
        entries += mark_menu;

        Gtk.ActionEntry mark_read = { ACTION_MARK_AS_READ, "mail-mark-read", TRANSLATABLE, null, null,
            on_mark_as_read };
        mark_read.label = _("Mark as _read");
        entries += mark_read;

        Gtk.ActionEntry mark_unread = { ACTION_MARK_AS_UNREAD, "mail-mark-unread", TRANSLATABLE, null,
            null, on_mark_as_unread };
        mark_unread.label = _("Mark as _unread");
        entries += mark_unread;
        
        Gtk.ActionEntry mark_starred = { ACTION_MARK_AS_STARRED, "starred", TRANSLATABLE, null, null,
            on_mark_as_starred };
        mark_starred.label = _("_Star");
        entries += mark_starred;

        Gtk.ActionEntry mark_unstarred = { ACTION_MARK_AS_UNSTARRED, "non-starred", TRANSLATABLE, null,
            null, on_mark_as_unstarred };
        mark_unstarred.label = _("U_nstar");
        entries += mark_unstarred;

        Gtk.ActionEntry copy_menu = { ACTION_COPY_MENU, null, TRANSLATABLE, "L", null,
            on_show_copy_menu };
        copy_menu.label = _("_Label");
        entries += copy_menu;

        Gtk.ActionEntry move_menu = { ACTION_MOVE_MENU, null, TRANSLATABLE, "M", null,
            on_show_move_menu };
        move_menu.label = _("_Move");
        entries += move_menu;

        Gtk.ActionEntry new_message = { ACTION_NEW_MESSAGE, null, TRANSLATABLE, "<Ctrl>N", null,
            on_new_message };
        new_message.label = _("_New Message");
        entries += new_message;
        add_accelerator("N", ACTION_NEW_MESSAGE);

        Gtk.ActionEntry reply_to_message = { ACTION_REPLY_TO_MESSAGE, null, TRANSLATABLE, "<Ctrl>R",
            null, on_reply_to_message_action };
        entries += reply_to_message;
        add_accelerator("R", ACTION_REPLY_TO_MESSAGE);
        
        Gtk.ActionEntry reply_all_message = { ACTION_REPLY_ALL_MESSAGE, null, TRANSLATABLE,
            "<Ctrl><Shift>R", null, on_reply_all_message_action };
        entries += reply_all_message;
        add_accelerator("<Shift>R", ACTION_REPLY_ALL_MESSAGE);
        
        Gtk.ActionEntry forward_message = { ACTION_FORWARD_MESSAGE, null, TRANSLATABLE, "<Ctrl>L", null,
            on_forward_message_action };
        entries += forward_message;
        add_accelerator("F", ACTION_FORWARD_MESSAGE);
        
        Gtk.ActionEntry delete_message = { ACTION_DELETE_MESSAGE, "user-trash-full", TRANSLATABLE,
            "A", null, on_delete_message };
        entries += delete_message;
        add_accelerator("Delete", ACTION_DELETE_MESSAGE);
        add_accelerator("BackSpace", ACTION_DELETE_MESSAGE);

        Gtk.ActionEntry zoom_in = { ACTION_ZOOM_IN, null, null, "<Ctrl>equal",
            null, on_zoom_in };
        entries += zoom_in;
        add_accelerator("equal", ACTION_ZOOM_IN);

        Gtk.ActionEntry zoom_out = { ACTION_ZOOM_OUT, null, null, "<Ctrl>minus",
            null, on_zoom_out };
        entries += zoom_out;
        add_accelerator("minus", ACTION_ZOOM_OUT);

        Gtk.ActionEntry zoom_normal = { ACTION_ZOOM_NORMAL, null, null, "<Ctrl>0",
            null, on_zoom_normal };
        entries += zoom_normal;
        add_accelerator("0", ACTION_ZOOM_NORMAL);

        return entries;
    }
    
    public async void connect_account_async(Geary.EngineAccount? new_account, Cancellable? cancellable) {
        if (account == new_account)
            return;
        
        // Disconnect the old account, if any.
        if (account != null) {
            cancel_folder();
            cancel_inbox();
            cancel_message();
            
            account.folders_added_removed.disconnect(on_folders_added_removed);
            
            main_window.title = GearyApplication.NAME;
            
            main_window.folder_list.remove_all_branches();
            
            if (inbox_folder != null) {
                try {
                    yield inbox_folder.close_async(cancellable);
                } catch (Error close_inbox_err) {
                    debug("Unable to close monitored inbox: %s", close_inbox_err.message);
                }
                
                inbox_folder.email_locally_appended.disconnect(on_inbox_new_email);
            }
            
            try {
                yield account.close_async(cancellable);
            } catch (Error close_err) {
                debug("Unable to close account %s: %s", account.to_string(), close_err.message);
            }
        }
        
        account = new_account;
        
        // Connect the new account, if any.
        if (account != null) {
            try {
                yield account.open_async(cancellable);
            } catch (Error open_err) {
                // TODO: Better error reporting to user
                debug("Unable to open account %s: %s", account.to_string(), open_err.message);
                
                account = null;
                
                GearyApplication.instance.panic();
            }
            
            account.folders_added_removed.connect(on_folders_added_removed);
            account.email_sent.connect(on_sent);
            
            if (account.settings.service_provider == Geary.ServiceProvider.YAHOO)
                main_window.title = GearyApplication.NAME + "!";
            
            main_window.folder_list.set_user_folders_root_name(_("Labels"));
            load_folders.begin(cancellable_folder);
        }
    }
    
    public async void disconnect_account_async(Cancellable? cancellable) throws Error {
        yield connect_account_async(null, cancellable);
    }
    
    private bool is_viewed_conversation(Geary.Conversation? conversation) {
        return conversation != null && selected_conversations.size > 0 &&
            Geary.Collection.get_first<Geary.Conversation>(selected_conversations) == conversation;
    }
    
    // Update widgets and such to match capabilities of the current folder ... sensitivity is handled
    // by other utility methods
    private void update_ui() {
        Gtk.Action delete_message = GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE);
        if (current_folder is Geary.FolderSupportsArchive) {
            delete_message.label = ARCHIVE_MESSAGE_LABEL;
            delete_message.tooltip = ARCHIVE_MESSAGE_TOOLTIP;
            delete_message.icon_name = ARCHIVE_MESSAGE_ICON_NAME;
        } else {
            // even if not Geary.FolderSupportsrRemove, use delete icons and label, although they
            // may be insensitive the entire time
            delete_message.label = DELETE_MESSAGE_LABEL;
            delete_message.tooltip = DELETE_MESSAGE_TOOLTIP;
            delete_message.icon_name = DELETE_MESSAGE_ICON_NAME;
        }
    }
    
    private async void load_folders(Cancellable? cancellable) {
        try {
            // pull down the root-level user folders and recursively add to sidebar
            Gee.Collection<Geary.Folder> folders = yield account.list_folders_async(null);
            if (folders != null)
                on_folders_added_removed(folders, null);
            else
                debug("no folders");
        } catch (Error err) {
            message("%s", err.message);
        }
    }
    
    private void on_folder_selected(Geary.Folder? folder) {
        if (folder == null) {
            debug("no folder selected");
            main_window.message_list_store.clear();
            
            return;
        }
        
        debug("Folder %s selected", folder.to_string());
        set_busy(true);
        do_select_folder.begin(folder, on_select_folder_completed);
    }
    
    private async void do_select_folder(Geary.Folder folder) throws Error {
        cancel_folder();
        main_window.message_list_store.clear();
        
        // stop monitoring for conversations and close the folder (but only if not the inbox_folder,
        // which we leave open for notifications)
        if (current_conversations != null) {
            yield current_conversations.stop_monitoring_async((current_folder != inbox_folder), null);
            current_conversations = null;
        } else if (current_folder != null && current_folder != inbox_folder) {
            yield current_folder.close_async();
        }
        
        if (folder != null)
            debug("switching to %s", folder.to_string());
        
        current_folder = folder;
        main_window.message_list_store.set_current_folder(current_folder);
        
        // The current folder may be null if the user rapidly switches between folders. If they have
        // done that then this folder selection is invalid anyways, so just return.
        if (current_folder == null) {
            warning("Can not open folder: %s", folder.to_string());
            return;
        }
        
        update_ui();
        
        current_conversations = new Geary.ConversationMonitor(current_folder, false,
            MessageListStore.REQUIRED_FIELDS);
        
        current_conversations.scan_started.connect(on_scan_started);
        current_conversations.scan_error.connect(on_scan_error);
        current_conversations.scan_completed.connect(on_scan_completed);
        current_conversations.conversations_added.connect(on_conversations_added);
        current_conversations.conversation_appended.connect(on_conversation_appended);
        current_conversations.conversation_trimmed.connect(on_conversation_trimmed);
        current_conversations.conversation_removed.connect(on_conversation_removed);
        current_conversations.email_flags_changed.connect(on_email_flags_changed);
        
        yield current_conversations.start_monitoring_async(cancellable_folder);
        
        // Do a quick-list of the messages in the local store), followed by a complete list if needed
        loading_local_only = true;
        current_conversations.lazy_load(-1, -1, Geary.Folder.ListFlags.LOCAL_ONLY, cancellable_folder);
    }
    
    public void on_scan_started() {
        main_window.message_list_view.enable_load_more = false;
        set_busy(true);
        
        scan_in_progress = true;
    }
    
    public void on_scan_error(Error err) {
        set_busy(false);
        
        scan_in_progress = false;
    }
    
    public void on_scan_completed() {
        set_busy(false);
        
        scan_in_progress = false;
        
        do_fetch_previews();
        
        main_window.message_list_view.enable_load_more = true;
        
        // Select first conversation.
        if (GearyApplication.instance.config.autoselect)
            main_window.message_list_view.select_first_conversation();
        
        do_second_pass_if_needed();
    }
    
    private void do_fetch_previews() {
        if (current_folder == null || !GearyApplication.instance.config.display_preview)
            return;
        
        Geary.Folder.ListFlags flags = (loading_local_only) ? Geary.Folder.ListFlags.LOCAL_ONLY
            : Geary.Folder.ListFlags.NONE;
        
        // sort the conversations so the previews are fetched from the newest to the oldest, matching
        // the user experience
        Gee.TreeSet<Geary.Conversation> sorted_conversations = new Gee.TreeSet<Geary.Conversation>(
            (CompareFunc) compare_conversation_descending);
        sorted_conversations.add_all(current_conversations.get_conversations());
        
        Gee.HashSet<Geary.EmailIdentifier> need_previews = new Gee.HashSet<Geary.EmailIdentifier>(
            Geary.Hashable.hash_func, Geary.Equalable.equal_func);
        foreach (Geary.Conversation conversation in sorted_conversations) {
            Geary.Email? need_preview = MessageListStore.email_for_preview(conversation);
            Geary.Email? current_preview = main_window.message_list_store.get_preview_for_conversation(conversation);
            
            // if all preview fields present and it's the same email, don't need to refresh
            if (need_preview != null && current_preview != null && need_preview.id.equals(current_preview.id) &&
                current_preview.fields.is_all_set(MessageListStore.WITH_PREVIEW_FIELDS)) {
                continue;
            }
            
            if (need_preview != null)
                need_previews.add(need_preview.id);
        }
        
        if (need_previews.size > 0) {
            current_folder.list_email_by_sparse_id_async.begin(need_previews,
                MessageListStore.WITH_PREVIEW_FIELDS, flags, cancellable_folder,
                on_fetch_previews_completed);
        }
    }
    
    private void on_fetch_previews_completed(Object? source, AsyncResult result) {
        if (current_folder == null || current_conversations == null)
            return;
        
        try {
            Gee.List<Geary.Email>? emails = current_folder.list_email_by_sparse_id_async.end(result);
            if (emails != null) {
                foreach (Geary.Email email in emails) {
                    Geary.Conversation? conversation = current_conversations.get_conversation_for_email(
                        email.id);
                    if (conversation != null)
                        main_window.message_list_store.set_preview_for_conversation(conversation, email);
                    else
                        debug("Couldn't find conversation for %s", email.id.to_string());
                }
            }
        } catch (Error err) {
            // Ignore NOT_FOUND, as that's entirely possible when waiting for the remote to open
            if (!(err is Geary.EngineError.NOT_FOUND))
                debug("Unable to fetch preview: %s", err.message);
        }
    }
    
    public void on_inbox_new_email(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        debug("on_inbox_new_email: %d locally appended", email_ids.size);
        do_notify_new_email.begin(email_ids);
    }
    
    public async void do_notify_new_email(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        try {
            Gee.List<Geary.Email>? list = yield inbox_folder.list_email_by_sparse_id_async(email_ids,
                NotificationBubble.REQUIRED_FIELDS | Geary.Email.Field.FLAGS, Geary.Folder.ListFlags.NONE,
                cancellable_inbox);
            if (list == null || list.size == 0) {
                debug("Warning: %d new emails, but none could be listed", email_ids.size);
                
                return;
            }
            
            int unread = 0;
            Geary.Email? last_unread = null;
            foreach (Geary.Email email in list) {
                if (email.email_flags.is_unread()) {
                    unread++;
                    last_unread = email;
                }
            }
            
            debug("do_notify_new_email: %d messages listed, %d unread", list.size, unread);
            
            NotificationBubble notification = new NotificationBubble();
            notification.invoked.connect(on_notification_bubble_invoked);
            if (unread == 1 && last_unread != null)
                yield notification.notify_one_message_async(last_unread, cancellable_inbox);
            else if (unread > 0)
                notification.notify_new_mail(unread);
        } catch (Error err) {
            debug("Unable to notify of new email: %s", err.message);
        }
    }

    private void on_notification_bubble_invoked(Geary.Email? email) {
        if(inbox_folder != null) {
            main_window.folder_list.select_path(inbox_folder.get_path());
            if(email != null) {
                Geary.Conversation? conversation = current_conversations.get_conversation_for_email(email.id);
                if(conversation != null) {
                    main_window.message_list_view.select_conversation(conversation);
                }
            }
        }
    }
    
    public void on_conversations_added(Gee.Collection<Geary.Conversation> conversations) {
        Gtk.Adjustment adjustment = (main_window.message_list_view.get_parent() as Gtk.ScrolledWindow)
            .get_vadjustment();
        int stage = ++conversations_added_counter;
        double scroll = adjustment.get_value();
        debug("Adding %d conversations (%d).", conversations.size, stage);
        foreach (Geary.Conversation c in conversations) {
            if (!main_window.message_list_store.has_conversation(c))
                main_window.message_list_store.append_conversation(c);
        }
        debug("Added %d conversations (%d).", conversations.size, stage);

        // If we are at the top of the message list we want to stay at the top. We need to spin the
        // event loop until they make it from the store to the view. We also don't want to have two
        // of these going, so if another conversation gets appended, we just return.
        if (scroll == 0) {
            while (Gtk.events_pending()) {
                if (Gtk.main_iteration() || conversations_added_counter != stage) {
                    return;
                }
            }
            adjustment.set_value(0);
        }
    }

    public void on_conversation_appended(Geary.Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        // If we're viewing this conversation, fetch the messages and add them to the view.
        if (main_window.message_list_store.has_conversation(conversation)) {
            main_window.message_list_store.update_conversation(conversation);
        }
        if (is_viewed_conversation(conversation))
            do_show_message.begin(conversation.get_email(Geary.Conversation.Ordering.NONE), cancellable_message,
                false, on_show_message_completed);
    }
    
    public void on_conversation_trimmed(Geary.Conversation conversation, Geary.Email email) {
        if (is_viewed_conversation(conversation))
            main_window.message_viewer.remove_message(email);
    }
    
    public void on_conversation_removed(Geary.Conversation conversation) {
        main_window.message_list_store.remove_conversation(conversation);
        if (!GearyApplication.instance.config.autoselect) {
            main_window.message_list_view.unselect_all();
        }
    }
    
    private void on_load_more() {
        debug("on_load_more");
        main_window.message_list_view.enable_load_more = false;
        
        Geary.EmailIdentifier? low_id = main_window.message_list_store.get_email_id_lowest();
        if (low_id == null)
            return;
        
        set_busy(true);
        current_conversations.load_by_id_async.begin(low_id, - FETCH_EMAIL_CHUNK_COUNT,
            Geary.Folder.ListFlags.EXCLUDING_ID, cancellable_folder, on_load_more_completed);
    }
    
    private void on_load_more_completed(Object? source, AsyncResult result) {
        debug("on load more completed");
        try {
            current_conversations.load_by_id_async.end(result);
        } catch (Error err) {
            debug("Error, unable to load conversations: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_email_flags_changed(Geary.Conversation conversation, Geary.Email email) {
        main_window.message_list_store.update_conversation(conversation, true);
        main_window.message_viewer.update_flags(email);
    }
    
    private void do_second_pass_if_needed() {
        if (loading_local_only) {
            loading_local_only = false;
            
            debug("Loading all emails now");
            current_conversations.lazy_load(-1, FETCH_EMAIL_CHUNK_COUNT, Geary.Folder.ListFlags.NONE,
                cancellable_folder);
        }
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_conversations_selected(Gee.Set<Geary.Conversation> selected) {
        debug("on_conversations_selected: %d", selected.size);
        
        cancel_message();

        selected_conversations = selected;
        
        // Disable message buttons until conversation loads.
        enable_message_buttons(false);
        
        if (selected.size == 1 && current_folder != null) {
            Geary.Conversation conversation = Geary.Collection.get_first(selected);
            do_show_message.begin(conversation.get_email(Geary.Conversation.Ordering.DATE_ASCENDING),
                cancellable_message, true, on_show_message_completed);
        } else if (current_folder != null) {
            main_window.message_viewer.show_multiple_selected(selected.size);
            if (selected.size > 1) {
                enable_multiple_message_buttons();
            } else {
                enable_message_buttons(false);
            }
        }
    }
    
    private async void do_show_message(Gee.Collection<Geary.Email> messages, Cancellable? 
        cancellable = null, bool clear_view = true) throws Error {
        Gee.List<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        set_busy(true);
        
        Gee.HashSet<Geary.Email> messages_to_add = new Gee.HashSet<Geary.Email>();
        
        // Clear view before we yield, to make sure it happens
        if (clear_view) {
            main_window.message_viewer.clear(current_folder);
            main_window.message_viewer.scroll_reset();
        }
        
        // Fetch full messages.
        foreach (Geary.Email email in messages) {
            Geary.Email full_email = yield current_folder.fetch_email_async(email.id,
                MessageViewer.REQUIRED_FIELDS | Geary.ComposedEmail.REQUIRED_REPLY_FIELDS,
                Geary.Folder.ListFlags.NONE, cancellable);
            
            if (cancellable.is_cancelled())
                throw new IOError.CANCELLED("do_select_message cancelled");
            
            messages_to_add.add(full_email);
            
            if (full_email.email_flags.is_unread())
                ids.add(full_email.id);
        }
        
        // Add messages.  message_viewer.add_message only adds new messages
        foreach (Geary.Email email in messages_to_add)
            main_window.message_viewer.add_message(email);
        
        main_window.message_viewer.unhide_last_email();
        
        // Mark as read.
        Geary.FolderSupportsMark? supports_mark = current_folder as Geary.FolderSupportsMark;
        if (supports_mark != null && ids.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            
            yield supports_mark.mark_email_async(ids, null, flags, cancellable);
        }
    }
    
    private void on_show_message_completed(Object? source, AsyncResult result) {
        try {
            do_show_message.end(result);
            enable_message_buttons(true);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Unable to show message: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_special_folder_type_changed(Geary.Folder folder, Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type) {
        main_window.folder_list.remove_folder(folder);
        main_window.folder_list.add_folder(folder);
    }
    
    private void on_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed) {
        
        if (added != null && added.size > 0) {
            foreach (Geary.Folder folder in added) {
                main_window.folder_list.add_folder(folder);
                main_window.main_toolbar.copy_folder_menu.add_folder(folder);
                main_window.main_toolbar.move_folder_menu.add_folder(folder);
                
                // monitor the Inbox for notifications
                if (folder.get_special_folder_type() == Geary.SpecialFolderType.INBOX && inbox_folder == null) {
                    inbox_folder = folder;
                    inbox_folder.email_locally_appended.connect(on_inbox_new_email);
                    
                    // select the inbox and get the show started
                    main_window.folder_list.select_path(folder.get_path());
                    inbox_folder.open_async.begin(false, cancellable_inbox);
                }
                
                folder.special_folder_type_changed.connect(on_special_folder_type_changed);
            }
            
            search_folders_for_children.begin(added);
        }
    }
    
    private async void search_folders_for_children(Gee.Collection<Geary.Folder> folders) {
        set_busy(true);
        Geary.NonblockingBatch batch = new Geary.NonblockingBatch();
        foreach (Geary.Folder folder in folders) {
            // Search for children unless Folder is absolutely certain it doesn't have any
            if (folder.has_children().is_possible())
                batch.add(new ListFoldersOperation(account, folder.get_path()));
        }
        
        debug("Listing %d folder children", batch.size);
        try {
            yield batch.execute_all_async();
        } catch (Error err) {
            debug("Unable to execute batch: %s", err.message);
            set_busy(false);
            
            return;
        }
        debug("Completed listing folder children");
        
        Gee.ArrayList<Geary.Folder> accumulator = new Gee.ArrayList<Geary.Folder>();
        foreach (int id in batch.get_ids()) {
            ListFoldersOperation op = (ListFoldersOperation) batch.get_operation(id);
            try {
                Gee.Collection<Geary.Folder> children = (Gee.Collection<Geary.Folder>) 
                    batch.get_result(id);
                accumulator.add_all(children);
            } catch (Error err2) {
                debug("Unable to list children of %s: %s", op.path.to_string(), err2.message);
            }
        }
        
        if (accumulator.size > 0)
            on_folders_added_removed(accumulator, null);
        
        set_busy(false);
    }
    
    private void cancel_folder() {
        Cancellable old_cancellable = cancellable_folder;
        cancellable_folder = new Cancellable();
        cancel_message();
        
        old_cancellable.cancel();
    }
     private void cancel_inbox() {
        Cancellable old_cancellable = cancellable_inbox;
        cancellable_inbox = new Cancellable();

        old_cancellable.cancel();
    }
    
    private void cancel_message() {
        Cancellable old_cancellable = cancellable_message;
        cancellable_message = new Cancellable();
        
        set_busy(false);
        
        old_cancellable.cancel();
    }
    
    // We need to include the second parameter, or valac doesn't recognize the function as matching
    // YorbaApplication.exiting's signature.
    private bool on_application_exiting(YorbaApplication sender, bool panicked) {
        if (close_composition_windows())
            return true;
        
        return sender.cancel_exit();
    }
    
    public void on_quit() {
        GearyApplication.instance.exit();
    }

    private void on_help() {
        try {
            if (GearyApplication.instance.is_installed()) {
                Gtk.show_uri(null, "ghelp:geary", Gdk.CURRENT_TIME);
            } else {
                Pid pid;
                File exec_dir = GearyApplication.instance.get_exec_dir();
                string[] argv = new string[3];
                argv[0] = "gnome-help";
                argv[1] = GearyApplication.SOURCE_ROOT_DIR + "/help/C/";
                argv[2] = null;
                if (!Process.spawn_async(exec_dir.get_path(), argv, null,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL, null, out pid)) {
                    debug("Failed to launch help locally.");
                }
            }
        } catch (Error error) {
            debug("Error showing help: %s", error.message);
            Gtk.Dialog dialog = new Gtk.Dialog.with_buttons("Error", null,
                Gtk.DialogFlags.DESTROY_WITH_PARENT, Gtk.Stock.CLOSE, Gtk.ResponseType.CLOSE, null);
            dialog.response.connect(() => { dialog.destroy(); });
            dialog.get_content_area().add(new Gtk.Label("Error showing help: %s".printf(error.message)));
            dialog.show_all();
            dialog.run();
        }
    }

    public void on_about() {
        Gtk.show_about_dialog(main_window,
            "program-name", GearyApplication.NAME,
            "comments", GearyApplication.DESCRIPTION,
            "authors", GearyApplication.AUTHORS,
            "copyright", GearyApplication.COPYRIGHT,
            "license", GearyApplication.LICENSE,
            "version", GearyApplication.VERSION,
            "website", GearyApplication.WEBSITE,
            "website-label", GearyApplication.WEBSITE_LABEL
        );
    }
    
    public void on_preferences() {
        PreferencesDialog dialog = new PreferencesDialog(GearyApplication.instance.config);
        dialog.run();
    }

    private Gee.List<Geary.EmailIdentifier> get_selected_ids(bool only_get_preview_message = false) {
        Gee.List<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Conversation conversation in selected_conversations) {
            if (only_get_preview_message) {
                Geary.Email? preview_message = MessageListStore.email_for_preview(conversation);
                if (preview_message != null) {
                    ids.add(preview_message.id);
                }
            } else {
                ids.add_all(conversation.get_email_ids());
            }
        }
        return ids;
    }

    private void mark_selected_conversations(Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove, bool only_get_preview_message = false) {
        Geary.FolderSupportsMark? supports_mark = current_folder as Geary.FolderSupportsMark;
        if (supports_mark == null)
            return;
        
        // Mark the emails.
        Gee.List<Geary.EmailIdentifier> ids = get_selected_ids(only_get_preview_message);
        if (ids.size > 0) {
            set_busy(true);
            supports_mark.mark_email_async.begin(ids, flags_to_add, flags_to_remove,
                cancellable_message, on_mark_complete);
        }
    }

    private void on_show_mark_menu() {
        bool unread_selected = false;
        bool read_selected = false;
        bool starred_selected = false;
        bool unstarred_selected = false;
        foreach (Geary.Conversation conversation in selected_conversations) {
            if (conversation.is_unread()) {
                unread_selected = true;
            } else {
                read_selected = true;
            }
            if (conversation.is_flagged()) {
                starred_selected = true;
            } else {
                unstarred_selected = true;
            }
        }
        var actions = GearyApplication.instance.actions;
        actions.get_action(ACTION_MARK_AS_READ).set_visible(unread_selected);
        actions.get_action(ACTION_MARK_AS_UNREAD).set_visible(read_selected);
        actions.get_action(ACTION_MARK_AS_STARRED).set_visible(unstarred_selected);
        actions.get_action(ACTION_MARK_AS_UNSTARRED).set_visible(starred_selected);
    }

    private void on_mark_conversation(Geary.Conversation conversation,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove, bool only_mark_preview = false) {
        Geary.FolderSupportsMark? supports_mark = current_folder as Geary.FolderSupportsMark;
        if (supports_mark == null)
            return;
        
        Gee.List<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        if (only_mark_preview) {
            Geary.Email? email = MessageListStore.email_for_preview(conversation);
            if (email != null) {
                ids.add(email.id);
            }
        } else {
            ids.add_all(conversation.get_email_ids());
        }
        
        if (ids.size > 0) {
            set_busy(true);
            supports_mark.mark_email_async.begin(ids, flags_to_add, flags_to_remove,
                cancellable_message, on_mark_complete);
        }
    }

    private void on_message_viewer_mark_message(Geary.Email message, Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove) {
        Geary.FolderSupportsMark? supports_mark = current_folder as Geary.FolderSupportsMark;
        if (supports_mark == null)
            return;
        
        set_busy(true);
        supports_mark.mark_single_email_async.begin(message.id, flags_to_add, flags_to_remove,
            cancellable_message, on_mark_complete);
    }
    
    private void on_mark_as_read() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_selected_conversations(null, flags);
    }

    private void on_mark_as_unread() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_selected_conversations(flags, null);
    }

    private void on_mark_as_starred() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_selected_conversations(flags, null, true);
    }

    private void on_mark_as_unstarred() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_selected_conversations(null, flags);
    }
    
    private void on_mark_complete() {
        set_busy(false);
    }

    private void on_show_copy_menu() {
        main_window.main_toolbar.copy_folder_menu.show();
    }

    private void on_show_move_menu() {
        main_window.main_toolbar.move_folder_menu.show();
    }

    private void on_copy_conversation(Geary.Folder destination) {
        // Nothing to do if nothing selected.
        if (selected_conversations == null || selected_conversations.size == 0)
            return;
        
        Gee.List<Geary.EmailIdentifier> ids = get_selected_ids();
        if (ids.size == 0)
            return;
        
        Geary.FolderSupportsCopy? supports_copy = current_folder as Geary.FolderSupportsCopy;
        if (supports_copy == null)
            return;
        
        set_busy(true);
        supports_copy.copy_email_async.begin(ids, destination.get_path(), cancellable_message,
            on_copy_complete);
    }

    private void on_copy_complete() {
        set_busy(false);
    }

    private void on_move_conversation(Geary.Folder destination) {
        // Nothing to do if nothing selected.
        if (selected_conversations == null || selected_conversations.size == 0)
            return;
        
        Gee.List<Geary.EmailIdentifier> ids = get_selected_ids();
        if (ids.size == 0)
            return;
        
        Geary.FolderSupportsMove? supports_move = current_folder as Geary.FolderSupportsMove;
        if (supports_move == null)
            return;
        
        set_busy(true);
        supports_move.move_email_async.begin(ids, destination.get_path(), cancellable_message,
            on_move_complete);
    }

    private void on_move_complete() {
        set_busy(false);
    }

    private void on_open_attachment(Geary.Attachment attachment) {
        open_uri("file://" + attachment.filepath);
    }

    private void on_save_attachments(Gee.List<Geary.Attachment> attachments) {
        Gtk.FileChooserAction action = attachments.size == 1
            ? Gtk.FileChooserAction.SAVE
            : Gtk.FileChooserAction.SELECT_FOLDER;
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(null, main_window, action,
            Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT, null);
        if (last_save_directory != null)
            dialog.set_current_folder(last_save_directory.get_path());
        dialog.set_current_name(attachments[0].filename);
        if (dialog.run() != Gtk.ResponseType.ACCEPT) {
            dialog.destroy();
            return;
        }

        // Get the selected location.
        string filename = dialog.get_filename();
        debug("Saving attachment to: %s", filename);

        // Save the attachments.
        // TODO Handle attachments with the same name being saved into the same directory.
        File destination = File.new_for_path(filename);
        last_save_directory = destination.get_parent();
        if (attachments.size == 1) {
            File source = File.new_for_path(attachments[0].filepath);
            source.copy_async.begin(destination, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null,
                null, on_save_completed);
        } else {
            foreach (Geary.Attachment attachment in attachments) {
                File dest_name = destination.get_child(attachment.filename);
                File source = File.new_for_path(attachment.filepath);
                debug("Saving %s to %s", source.get_path(), dest_name.get_path());
                source.copy_async.begin(dest_name, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null,
                    null, on_save_completed);
            }
        }

        dialog.destroy();
    }

    private void on_save_completed(Object? source, AsyncResult result) {
        try {
            ((File) source).copy_async.end(result);
        } catch (Error error) {
            warning("Failed to copy attachment to destination: %s", error.message);
        }
    }

    // Opens a link in an external browser.
    private void open_uri(string _link) {
        string link = _link;
        
        // Support web URLs that ommit the protocol.
        if (!link.contains(":"))
            link = "http://" + link;
        
        try {
            Gtk.show_uri(main_window.get_screen(), link, Gdk.CURRENT_TIME);
        } catch (Error err) {
            debug("Unable to open URL. %s", err.message);
        }
    }
    
    private bool close_composition_windows() {
        // We want to allow the user to cancel a quit when they have unsent text.
        
        // We are modifying the list as we go, so we can't simply iterate through it.
        while (composer_windows.size > 0) {
            ComposerWindow composer_window = composer_windows.first();
            if (!composer_window.should_close())
                return false;
            
            // This will remove composer_window from composer_windows.
            // See GearyController.on_composer_window_destroy.
            composer_window.destroy();
        }
        
        // If we deleted all composer windows without the user cancelling, we can exit.
        return true;
    }
    
    private void create_compose_window(Geary.ComposedEmail? prefill = null) {
        ComposerWindow window = new ComposerWindow(prefill);
        window.set_position(Gtk.WindowPosition.CENTER);
        window.send.connect(on_send);
        
        // We want to keep track of the open composer windows, so we can allow the user to cancel
        // an exit without losing their data.
        composer_windows.add(window);
        window.destroy.connect(on_composer_window_destroy);
        
        window.show_all();
    }
    
    private void on_composer_window_destroy(Gtk.Widget sender) {
        composer_windows.remove((ComposerWindow) sender);
    }
    
    private void on_new_message() {
        create_compose_window();
    }
    
    private void on_reply_to_message(Geary.Email message) {
        create_compose_window(new Geary.ComposedEmail.as_reply(new DateTime.now_local(),
            get_from(), message));
    }
    
    private void on_reply_to_message_action() {
        Geary.Email? message = main_window.message_viewer.get_last_message();
        if (message != null)
            on_reply_to_message(message);
    }
    
    private void on_reply_all_message(Geary.Email message) {
        create_compose_window(new Geary.ComposedEmail.as_reply_all(new DateTime.now_local(),
            get_from(), message));
    }
    
    private void on_reply_all_message_action() {
        Geary.Email? message = main_window.message_viewer.get_last_message();
        if (message != null)
            on_reply_all_message(message);
    }
    
    private void on_forward_message(Geary.Email message) {
        create_compose_window(new Geary.ComposedEmail.as_forward(new DateTime.now_local(),
            get_from(), message));
    }
    
    private void on_forward_message_action() {
        Geary.Email? message = main_window.message_viewer.get_last_message();
        if (message != null)
            on_forward_message(message);
    }
    
    // This method is used for both removing and archive a message; currently Geary only supports
    // one or the other in a folder
    private void on_delete_message() {
        // Prevent deletes of the same conversation from repeating.
        if (is_viewed_conversation(last_deleted_conversation))
            return;
        
        // There should always be at least one conversation selected here, otherwise the archive
        // button is disabled, but better safe than segfaulted.
        last_deleted_conversation = selected_conversations.size > 0
            ? Geary.Collection.get_first<Geary.Conversation>(selected_conversations) : null;

        // If the user clicked the toolbar button, we want to move focus back to the message list.
        main_window.message_list_view.grab_focus();
        set_busy(true);

        // Collect all the emails into one pool and then delete.
        Gee.Set<Geary.Email> all_emails = new Gee.TreeSet<Geary.Email>();
        foreach (Geary.Conversation conversation in selected_conversations)
            all_emails.add_all(conversation.get_email(Geary.Conversation.Ordering.NONE));
        
        delete_messages.begin(all_emails, cancellable_folder, on_delete_messages_completed);
    }
    
    // This method is used for both removing and archive a message; currently Geary only supports
    // one or the other in a folder.  This will try archiving first, then remove.
    private async void delete_messages(Gee.Collection<Geary.Email> messages, Cancellable? cancellable)
        throws Error {
        Gee.List<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Email email in messages)
            list.add(email.id);
        
        Geary.FolderSupportsArchive? supports_archive = current_folder as Geary.FolderSupportsArchive;
        if (supports_archive != null) {
            yield supports_archive.archive_email_async(list, cancellable);
            
            return;
        }
        
        Geary.FolderSupportsRemove? supports_remove = current_folder as Geary.FolderSupportsRemove;
        if (supports_remove != null) {
            yield supports_remove.remove_email_async(list, cancellable);
            
            return;
        }
        
        debug("Folder %s supports neither remove nor archive", current_folder.to_string());
    }

    private void on_delete_messages_completed(Object? source, AsyncResult result) {
        try {
            delete_messages.end(result);
        } catch (Error err) {
            debug("Error, unable to delete messages: %s", err.message);
        }
        
        set_busy(false);
    }
    
    private void on_zoom_in() {
        main_window.message_viewer.zoom_in();
    }

    private void on_zoom_out() {
        main_window.message_viewer.zoom_out();
    }

    private void on_zoom_normal() {
        main_window.message_viewer.zoom_level = 1.0f;
    }
    
    private Geary.RFC822.MailboxAddress get_sender() {
        string username;
        try {
            // TODO: Multiple accounts.
            username = Geary.Engine.get_usernames().get(0);
        } catch (Error e) {
            error("Unable to get username. Error: %s", e.message);
        }
        
        return new Geary.RFC822.MailboxAddress(account.settings.real_name, username);
    }
        
    private Geary.RFC822.MailboxAddresses get_from() {
        return new Geary.RFC822.MailboxAddresses.single(get_sender());
    }
        
    private void on_send(ComposerWindow composer_window) {
        account.send_email_async.begin(composer_window.get_composed_email(get_from()));
        composer_window.destroy();
    }

    private void on_sent(Geary.RFC822.Message rfc822) {
        NotificationBubble.play_sound("message-sent-email");
    }
    
    public void set_busy(bool is_busy) {
        busy_count += is_busy ? 1 : -1;
        if (busy_count < 0)
            busy_count = 0;
        
        main_window.set_busy(busy_count > 0);
    }

    private void on_display_preview_changed() {
        do_fetch_previews();
        main_window.message_list_view.style_set(null);
        main_window.message_list_view.refresh();
    }
    
    public void on_link_selected(string link) {
        const string MAILTO = "mailto:";
        if (link.down().has_prefix(MAILTO)) {
            compose_mailto(link);
        } else {
            open_uri(link);
        }
    }

    // Disables all single-message buttons and enables all multi-message buttons.
    public void enable_multiple_message_buttons(){
        // Single message only buttons.
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = false;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = false;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = false;

        // Mutliple message buttons.
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive =
            (current_folder is Geary.FolderSupportsRemove) || (current_folder is Geary.FolderSupportsArchive);
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive =
            current_folder is Geary.FolderSupportsMark;
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).sensitive =
            current_folder is Geary.FolderSupportsCopy;
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).sensitive =
            current_folder is Geary.FolderSupportsMove;
    }

    // Enables or disables the message buttons on the toolbar.
    public void enable_message_buttons(bool sensitive) {
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive = sensitive
            && ((current_folder is Geary.FolderSupportsRemove) || (current_folder is Geary.FolderSupportsArchive));
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupportsMark);
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupportsCopy);
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupportsMove);
    }

    public void compose_mailto(string mailto) {
        create_compose_window(new Geary.ComposedEmail.from_mailto(mailto, get_from()));
    }
}

