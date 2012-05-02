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
    
    private class FetchSpecialFolderOperation : Geary.NonblockingBatchOperation {
        public Geary.Account account;
        public Geary.SpecialFolder special_folder;
        
        public FetchSpecialFolderOperation(Geary.Account account, Geary.SpecialFolder special_folder) {
            this.account = account;
            this.special_folder = special_folder;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            return yield account.fetch_folder_async(special_folder.path);
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
    
    private const int FETCH_EMAIL_CHUNK_COUNT = 50;
    
    public MainWindow main_window { get; private set; }
    public bool enable_load_more { get; set; default = true; }
    
    private Cancellable cancellable_folder = new Cancellable();
    private Cancellable cancellable_message = new Cancellable();
    private Geary.EngineAccount? account = null;
    private Geary.Folder? current_folder = null;
    private Geary.Conversations? current_conversations = null;
    private bool loading_local_only = true;
    private int busy_count = 0;
    private Geary.Conversation[] selected_conversations = new Geary.Conversation[0];
    private Geary.Conversation? last_deleted_conversation = null;
    private bool scan_in_progress = false;
    
    public GearyController() {
        // Setup actions.
        GearyApplication.instance.actions.add_actions(create_actions(), this);
        GearyApplication.instance.ui_manager.insert_action_group(
            GearyApplication.instance.actions, 0);
        GearyApplication.instance.load_ui_file("accelerators.ui");
        GearyApplication.instance.config.display_preview_changed.connect(on_display_preview_changed);
        
        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow();
        
        enable_message_buttons(false);
        
        main_window.message_list_view.conversations_selected.connect(on_conversations_selected);
        main_window.message_list_view.load_more.connect(on_load_more);
        main_window.message_list_view.mark_conversation.connect(on_mark_conversation);
        main_window.folder_list.folder_selected.connect(on_folder_selected);
        main_window.message_viewer.link_selected.connect(on_link_selected);
        main_window.message_viewer.reply_to_message.connect(on_reply_to_message);
        main_window.message_viewer.reply_all_message.connect(on_reply_all_message);
        main_window.message_viewer.forward_message.connect(on_forward_message);
        main_window.message_viewer.mark_message.connect(on_message_viewer_mark_message);
        
        main_window.message_list_view.grab_focus();
        
        set_busy(false);
    }
    
    ~GearyController() {
        if (account != null)
            account.folders_added_removed.disconnect(on_folders_added_removed);
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
        
        Gtk.ActionEntry mark_menu = { ACTION_MARK_AS_MENU, null, TRANSLATABLE, null,
            null, on_show_mark_menu };
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

        Gtk.ActionEntry new_message = { ACTION_NEW_MESSAGE, null, TRANSLATABLE, "<Ctrl>N", null,
            on_new_message };
        new_message.label = _("_New Message");
        entries += new_message;
        add_accelerator("N", ACTION_NEW_MESSAGE);

        Gtk.ActionEntry reply_to_message = { ACTION_REPLY_TO_MESSAGE, null, TRANSLATABLE, "<Ctrl>R",
            null, on_reply_to_message };
        entries += reply_to_message;
        add_accelerator("R", ACTION_REPLY_TO_MESSAGE);
        
        Gtk.ActionEntry reply_all_message = { ACTION_REPLY_ALL_MESSAGE, null, TRANSLATABLE,
            "<Ctrl><Shift>R", null, on_reply_all_message };
        entries += reply_all_message;
        add_accelerator("<Shift>R", ACTION_REPLY_ALL_MESSAGE);
        
        Gtk.ActionEntry forward_message = { ACTION_FORWARD_MESSAGE, null, TRANSLATABLE, "<Ctrl>L", null,
            on_forward_message };
        entries += forward_message;
        add_accelerator("F", ACTION_FORWARD_MESSAGE);
        
        Gtk.ActionEntry delete_message = { ACTION_DELETE_MESSAGE, null, TRANSLATABLE, "A",
            null, on_delete_message };
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
    
    private bool is_viewed_conversation(Geary.Conversation? conversation) {
        return conversation != null && selected_conversations.length > 0 &&
            selected_conversations[0] == conversation;
    }
    
    public void start(Geary.EngineAccount account) {
        this.account = account;
        
        account.folders_added_removed.connect(on_folders_added_removed);
        
        // Personality-specific setup.
        if (account.delete_is_archive()) {
            GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).label =
                _("Archive Message");
            GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).tooltip =
                _("Archive the selected conversation");
        }
        
        main_window.folder_list.set_user_folders_root_name(account.get_user_folders_label());
        
        main_window.show_all();
        do_start.begin(cancellable_folder);
    }
    
    private async void do_start(Cancellable? cancellable) {
        try {
            // add all the special folders, which are assumed to always exist
            Geary.SpecialFolderMap? special_folders = account.get_special_folder_map();
            if (special_folders != null) {
                Geary.NonblockingBatch batch = new Geary.NonblockingBatch();
                foreach (Geary.SpecialFolder special_folder in special_folders.get_all())
                    batch.add(new FetchSpecialFolderOperation(account, special_folder));
                
                debug("Listing special folders");
                yield batch.execute_all_async(cancellable);
                debug("Completed list of special folders");
                
                foreach (int id in batch.get_ids()) {
                    FetchSpecialFolderOperation op = (FetchSpecialFolderOperation) 
                        batch.get_operation(id);
                    try {
                        Geary.Folder folder = (Geary.Folder) batch.get_result(id);
                        main_window.folder_list.add_special_folder(op.special_folder, folder);
                    } catch (Error inner_error) {
                        message("Unable to fetch special folder %s: %s", 
                            op.special_folder.path.to_string(), inner_error.message);
                    }
                }
                
                if (cancellable.is_cancelled())
                    return;
                
                // If inbox is specified, select that
                Geary.SpecialFolder? inbox = special_folders.get_folder(Geary.SpecialFolderType.INBOX);
                if (inbox != null)
                    main_window.folder_list.select_path(inbox.path);
            }
            
            // pull down the root-level user folders
            Gee.Collection<Geary.Folder> folders = yield account.list_folders_async(null);
            if (folders != null)
                on_folders_added_removed(folders, null);
            else
                debug("no folders");
        } catch (Error err) {
            message("%s", err.message);
        }
    }
    
    public void stop() {
        cancel_folder();
        cancel_message();
        account = null;
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
        
        if (current_folder != null) {
            yield current_folder.close_async();
        }
        
        current_conversations = null;
        current_folder = folder;
        main_window.message_list_store.set_current_folder(current_folder);

        yield current_folder.open_async(false, cancellable_folder);

        // The current folder may be null if the user rapidly switches between folders. If they have
        // done that then this folder selection is invalid anyways, so just return.
        if (current_folder == null) {
            warning("Can not open folder: %s", folder.to_string());
            return;
        }
        
        current_conversations = new Geary.Conversations(current_folder, 
            MessageListStore.REQUIRED_FIELDS);
            
        current_conversations.monitor_new_messages(cancellable_folder);
        
        current_conversations.scan_started.connect(on_scan_started);
        current_conversations.scan_error.connect(on_scan_error);
        current_conversations.scan_completed.connect(on_scan_completed);
        current_conversations.conversations_added.connect(on_conversations_added);
        current_conversations.conversation_appended.connect(on_conversation_appended);
        current_conversations.conversation_trimmed.connect(on_conversation_trimmed);
        current_conversations.conversation_removed.connect(on_conversation_removed);
        current_conversations.email_flags_changed.connect(on_email_flags_changed);
        
        // Do a quick-list of the messages (which should return what's in the local store) if
        // supported by the Folder, followed by a complete list if needed
        loading_local_only = true;
        
        // Load all conversations from the DB.
        current_conversations.lazy_load(-1, -1, Geary.Folder.ListFlags.LOCAL_ONLY, cancellable_folder);
    }
    
    public void on_scan_started(Geary.EmailIdentifier? id, int low, int count) {
        debug("on scan started. id = %s low = %d count = %d", id != null ? id.to_string() : "(null)", 
            low, count);
        main_window.message_list_view.enable_load_more = false;
        set_busy(true);
        
        scan_in_progress = true;
    }
    
    public void on_scan_error(Error err) {
        debug("Scan error: %s", err.message);
        set_busy(false);
        
        scan_in_progress = false;
    }
    
    public void on_scan_completed() {
        debug("on scan completed");
        
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
        
        foreach (Geary.Conversation conversation in sorted_conversations) {
            Geary.Email? need_preview = MessageListStore.email_for_preview(conversation);
            Geary.Email? current_preview = main_window.message_list_store.get_preview_for_conversation(conversation);
            
            // if all preview fields present and it's the same email, don't need to refresh
            if (need_preview != null && current_preview != null && need_preview.id.equals(current_preview.id) &&
                current_preview.fields.is_all_set(MessageListStore.WITH_PREVIEW_FIELDS)) {
                continue;
            }
            
            if (need_preview != null) {
                current_folder.fetch_email_async.begin(need_preview.id, MessageListStore.WITH_PREVIEW_FIELDS,
                    flags, cancellable_folder, on_fetch_preview_completed);
            }
        }
    }
    
    private void on_fetch_preview_completed(Object? source, AsyncResult result) {
        if (current_folder == null || current_conversations == null)
            return;
        
        try {
            Geary.Email email = current_folder.fetch_email_async.end(result);
            Geary.Conversation? conversation = current_conversations.get_conversation_for_email(email.id);
            
            if (conversation != null) {
                main_window.message_list_store.set_preview_for_conversation(conversation, email);
            } else
                debug("Couldn't find conversation for %s", email.id.to_string());
        } catch (Error err) {
            // Ignore NOT_FOUND, as that's entirely possible when waiting for the remote to open
            if (!(err is Geary.EngineError.NOT_FOUND))
                debug("Unable to fetch preview: %s", err.message);
        }
    }
    
    public void on_conversations_added(Gee.Collection<Geary.Conversation> conversations) {
        debug("adding %d conversations...", conversations.size);
        foreach (Geary.Conversation c in conversations) {
            if (!main_window.message_list_store.has_conversation(c))
                main_window.message_list_store.append_conversation(c);
        }
        debug("added %d conversations", conversations.size);
    }
    
    public void on_conversation_appended(Geary.Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        // If we're viewing this conversation, fetch the messages and add them to the view.
        if (main_window.message_list_store.has_conversation(conversation)) {
            main_window.message_list_store.update_conversation(conversation);
        }
        if (is_viewed_conversation(conversation))
            do_show_message.begin(conversation.get_email(Geary.Conversation.Ordering.NONE), cancellable_message,
                on_show_message_completed);
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
    
    private void on_conversations_selected(Geary.Conversation[] conversations) {
        cancel_message();

        selected_conversations = conversations;
        
        // Disable message buttons until conversation loads.
        enable_message_buttons(false);
        
        if (conversations.length == 1 && current_folder != null) {
            do_show_message.begin(conversations[0].get_email(Geary.Conversation.Ordering.DATE_ASCENDING),
                cancellable_message, on_show_message_completed);
        } else if (current_folder != null) {
            main_window.message_viewer.show_multiple_selected(conversations.length);
            if (conversations.length > 1) {
                enable_multiple_message_buttons();
            } else {
                enable_message_buttons(false);
            }
        }
    }
    
    private async void do_show_message(Gee.Collection<Geary.Email> messages, Cancellable? 
        cancellable = null) throws Error {
        Gee.List<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        set_busy(true);
        
        Gee.HashSet<Geary.Email> messages_to_add = new Gee.HashSet<Geary.Email>();
        
        // Fetch full messages.
        foreach (Geary.Email email in messages) {
            Geary.Email full_email = yield current_folder.fetch_email_async(email.id,
                MessageViewer.REQUIRED_FIELDS | Geary.ComposedEmail.REQUIRED_REPLY_FIELDS,
                Geary.Folder.ListFlags.NONE, cancellable);
            
            if (cancellable.is_cancelled())
                throw new IOError.CANCELLED("do_select_message cancelled");
            
            messages_to_add.add(full_email);
            
            if (full_email.properties.email_flags.is_unread())
                ids.add(full_email.id);
        }
        
        // Clear message viewer and add messages.
        main_window.message_viewer.clear();
        foreach (Geary.Email email in messages_to_add)
            main_window.message_viewer.add_message(email);
        
        main_window.message_viewer.scroll_to_first_unread();
        
        // Mark as read.
        if (ids.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            
            yield current_folder.mark_email_async(ids, null, flags, cancellable);
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
    
    private void on_folders_added_removed(Gee.Collection<Geary.Folder>? added,
        Gee.Collection<Geary.Folder>? removed) {
        
        if (added != null && added.size > 0) {
            Gee.Set<Geary.FolderPath>? ignored_paths = account.get_ignored_paths();
            
            Gee.ArrayList<Geary.Folder> skipped = new Gee.ArrayList<Geary.Folder>();
            foreach (Geary.Folder folder in added) {
                if (ignored_paths != null && ignored_paths.contains(folder.get_path()))
                    skipped.add(folder);
                else
                    main_window.folder_list.add_folder(folder);
            }
            
            Gee.Collection<Geary.Folder> remaining = added;
            if (skipped.size > 0) {
                remaining = new Gee.ArrayList<Geary.Folder>();
                remaining.add_all(added);
                remaining.remove_all(skipped);
            }
            
            search_folders_for_children.begin(remaining);
        }
    }
    
    private async void search_folders_for_children(Gee.Collection<Geary.Folder> folders) {
        set_busy(true);
        Geary.NonblockingBatch batch = new Geary.NonblockingBatch();
        foreach (Geary.Folder folder in folders)
            batch.add(new ListFoldersOperation(account, folder.get_path()));
        
        debug("Listing folder children");
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
    
    private void cancel_message() {
        Cancellable old_cancellable = cancellable_message;
        cancellable_message = new Cancellable();
        
        set_busy(false);
        
        old_cancellable.cancel();
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
                argv[1] = GearyApplication.SOURCE_ROOT_DIR + "/help";
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

        // Mark the emails.
        Gee.List<Geary.EmailIdentifier> ids = get_selected_ids(only_get_preview_message);
        if (ids.size > 0) {
            set_busy(true);
            current_folder.mark_email_async.begin(ids, flags_to_add, flags_to_remove,
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
            current_folder.mark_email_async.begin(ids, flags_to_add, flags_to_remove,
                cancellable_message, on_mark_complete);
        }
    }

    private void on_message_viewer_mark_message(Geary.EmailFlags? flags_to_add,
        Geary.EmailFlags? flags_to_remove) {

        Gee.List<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        ids.add(get_email_from_message_viewer().id);
        set_busy(true);
        current_folder.mark_email_async.begin(ids, flags_to_add, flags_to_remove,
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
    
    private void create_compose_window(Geary.ComposedEmail? prefill = null) {
        ComposerWindow w = new ComposerWindow(prefill);
        w.set_position(Gtk.WindowPosition.CENTER);
        w.send.connect(on_send);
        
        w.show_all();
    }
    
    private void on_new_message() {
        create_compose_window();
    }
    
    private Geary.Email get_email_from_message_viewer() {
        return main_window.message_viewer.active_email == null ?
            main_window.message_viewer.messages.last() : main_window.message_viewer.active_email;
    }
    
    private void on_reply_to_message() {
        create_compose_window(new Geary.ComposedEmail.as_reply(new DateTime.now_local(),
            get_from(), get_email_from_message_viewer()));
    }
    
    private void on_reply_all_message() {
        create_compose_window(new Geary.ComposedEmail.as_reply_all(new DateTime.now_local(),
            get_from(), get_email_from_message_viewer()));
    }
    
    private void on_forward_message() {
        create_compose_window(new Geary.ComposedEmail.as_forward(new DateTime.now_local(),
            get_from(), get_email_from_message_viewer()));
    }
    
    private void on_delete_message() {
        // Prevent deletes of the same conversation from repeating.
        if (is_viewed_conversation(last_deleted_conversation))
            return;
        
        // There should always be at least one conversation selected here, otherwise the archive
        // button is disabled, but better safe than segfaulted.
        last_deleted_conversation = selected_conversations.length > 0 ? selected_conversations[0] : null;

        // If the user clicked the toolbar button, we want to move focus back to the message list.
        main_window.message_list_view.grab_focus();
        set_busy(true);

        // Collect all the emails into one pool and then delete.
        Gee.Set<Geary.Email> all_emails = new Gee.TreeSet<Geary.Email>();
        foreach (Geary.Conversation conversation in selected_conversations)
            all_emails.add_all(conversation.get_email(Geary.Conversation.Ordering.NONE));
        
        delete_messages.begin(all_emails, cancellable_folder, on_delete_messages_completed);
    }
    
    private async void delete_messages(Gee.Collection<Geary.Email> messages, Cancellable? cancellable)
        throws Error {
        Gee.List<Geary.EmailIdentifier> list = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.Email email in messages)
            list.add(email.id);
        
        yield current_folder.remove_email_async(list, cancellable);
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
        
        Geary.AccountInformation acct_info = account.get_account_information();
        return new Geary.RFC822.MailboxAddress(acct_info.real_name, username);
    }
        
    private Geary.RFC822.MailboxAddresses get_from() {
        return new Geary.RFC822.MailboxAddresses.single(get_sender());
    }
        
    private void on_send(ComposerWindow cw) {
        account.send_email_async.begin(cw.get_composed_email(get_from()));
        cw.destroy();
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
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive = true;
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive = true;
    }
    
    // Enables or disables the message buttons on the toolbar.
    public void enable_message_buttons(bool sensitive) {
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive = sensitive;
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive = sensitive;
    }

    public void compose_mailto(string mailto) {
        create_compose_window(new Geary.ComposedEmail.from_mailto(mailto, get_from()));
    }
}

