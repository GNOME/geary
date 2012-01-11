/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Primary controller object for Geary.
public class GearyController {
    
    private class FetchPreviewOperation : Geary.NonblockingBatchOperation {
        public MainWindow owner;
        public Geary.Folder folder;
        public Geary.EmailIdentifier email_id;
        public Geary.Conversation conversation;
        
        public FetchPreviewOperation(MainWindow owner, Geary.Folder folder,
            Geary.EmailIdentifier email_id, Geary.Conversation conversation) {
            this.owner = owner;
            this.folder = folder;
            this.email_id = email_id;
            this.conversation = conversation;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            Geary.Email? preview = yield folder.fetch_email_async(email_id,
                MessageListStore.WITH_PREVIEW_FIELDS, cancellable);
            if (preview != null)
                owner.message_list_store.set_preview_for_conversation(conversation, preview);
            
            return null;
        }
    }
    
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
    public const string ACTION_DONATE = "GearyDonate";
    public const string ACTION_ABOUT = "GearyAbout";
    public const string ACTION_QUIT = "GearyQuit";
    public const string ACTION_NEW_MESSAGE = "GearyNewMessage";
    public const string ACTION_DELETE_MESSAGE = "GearyDeleteMessage";
    public const string ACTION_DEBUG_PRINT = "GearyDebugPrint";
    public const string ACTION_PREFERENCES = "GearyPreferences";
    
    private const int FETCH_EMAIL_CHUNK_COUNT = 50;
    
    public MainWindow main_window { get; private set; }
    public bool enable_load_more { get; set; default = true; }
    
    private Cancellable cancellable_folder = new Cancellable();
    private Cancellable cancellable_message = new Cancellable();
    private Geary.EngineAccount? account = null;
    private Geary.Folder? current_folder = null;
    private Geary.Conversations? current_conversations = null;
    private bool second_list_pass_required = false;
    private int busy_count = 0;
    private Geary.Conversation? current_conversation = null;
    private Geary.Conversation? last_deleted_conversation = null;
    
    public GearyController() {
        // Setup actions.
        GearyApplication.instance.actions.add_actions(create_actions(), this);
        GearyApplication.instance.ui_manager.insert_action_group(
            GearyApplication.instance.actions, 0);
        GearyApplication.instance.load_ui_file("accelerators.ui");
        
        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow();
        
        GearyApplication.instance.actions.get_action(GearyController.ACTION_DELETE_MESSAGE).sensitive
            = false;
        
        main_window.message_list_view.conversation_selected.connect(on_conversation_selected);
        main_window.message_list_view.load_more.connect(on_load_more);
        main_window.folder_list_view.folder_selected.connect(on_folder_selected);
        
        main_window.message_list_view.grab_focus();
        
        set_busy(false);
    }
    
    ~GearyController() {
        if (account != null)
            account.folders_added_removed.disconnect(on_folders_added_removed);
    }
    
    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] entries = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry prefs = { ACTION_PREFERENCES, null, TRANSLATABLE, null, null, on_preferences };
        prefs.label = _("_Preferences");
        entries += prefs;
        
        Gtk.ActionEntry donate = { ACTION_DONATE, null, TRANSLATABLE, null, null, on_donate };
        donate.label = _("_Donate");
        entries += donate;
        
        Gtk.ActionEntry about = { ACTION_ABOUT, Gtk.Stock.ABOUT, TRANSLATABLE, null, null, on_about };
        about.label = _("_About");
        entries += about;
        
        Gtk.ActionEntry quit = { ACTION_QUIT, Gtk.Stock.QUIT, TRANSLATABLE, "<Ctrl>Q", null, on_quit };
        quit.label = _("_Quit");
        entries += quit;
        
        Gtk.ActionEntry new_message = { ACTION_NEW_MESSAGE, Gtk.Stock.NEW, TRANSLATABLE, "<Ctrl>N", 
            null, on_new_message };
        new_message.label = _("_New Message");
        entries += new_message;
        
        Gtk.ActionEntry delete_message = { ACTION_DELETE_MESSAGE, Gtk.Stock.CLOSE, TRANSLATABLE, "Delete",
            null, on_delete_message };
        entries += delete_message;
        
        Gtk.ActionEntry secret_debug = { ACTION_DEBUG_PRINT, null, null, "<Ctrl><Alt>P",
            null, debug_print_selected };
        entries += secret_debug;
        
        return entries;
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
        
        main_window.folder_list_store.set_user_folders_root_name(account.get_user_folders_label());
        
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
                        main_window.folder_list_store.add_special_folder(op.special_folder, folder);
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
                    main_window.folder_list_view.select_path(inbox.path);
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
        
        current_folder = folder;
        
        yield current_folder.open_async(false, cancellable_folder);
        
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
        current_conversations.updated_placeholders.connect(on_updated_placeholders);
        
        current_folder.email_flags_changed.connect(on_email_flags_changed);
        
        // Do a quick-list of the messages (which should return what's in the local store) if
        // supported by the Folder, followed by a complete list if needed
        second_list_pass_required =
            current_folder.get_supported_list_flags().is_all_set(Geary.Folder.ListFlags.FAST);
        
        // Load all conversations from the DB.
        current_conversations.lazy_load(-1, -1, Geary.Folder.ListFlags.FAST, cancellable_folder);
    }
    
    public void on_scan_started(Geary.EmailIdentifier? id, int low, int count) {
        debug("on scan started. id = %s low = %d count = %d", id != null ? id.to_string() : "(null)", 
            low, count);
        main_window.message_list_view.enable_load_more = false;
        set_busy(true);
    }
    
    public void on_scan_error(Error err) {
        debug("Scan error: %s", err.message);
    }
    
    public void on_scan_completed() {
        debug("on scan completed");
        
        set_busy(false);
        
        do_fetch_previews.begin(cancellable_folder);
        main_window.message_list_view.enable_load_more = true;
        
        // Select first conversation.
        if (!second_list_pass_required && GearyApplication.instance.config.autoselect)
            main_window.message_list_view.select_first_conversation();
    }
    
    public void on_conversations_added(Gee.Collection<Geary.Conversation> conversations) {
        debug("on conversation added");
        foreach (Geary.Conversation c in conversations) {
            if (!main_window.message_list_store.has_conversation(c))
                main_window.message_list_store.append_conversation(c);
        }
    }
    
    public void on_conversation_appended(Geary.Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        main_window.message_list_store.update_conversation(conversation);
    }
    
    public void on_conversation_trimmed(Geary.Conversation conversation, Geary.Email email) {
        main_window.message_list_store.update_conversation(conversation);
    }
    
    public void on_conversation_removed(Geary.Conversation conversation) {
        main_window.message_list_store.remove_conversation(conversation);
    }
    
    public void on_updated_placeholders(Geary.Conversation conversation,
        Gee.Collection<Geary.Email> email) {
        main_window.message_list_store.update_conversation(conversation);
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
    
    private void on_email_flags_changed(Gee.Map<Geary.EmailIdentifier, Geary.EmailFlags> map) {
        foreach (Geary.EmailIdentifier id in map.keys)
            main_window.message_list_store.update_flags(id, map.get(id));
    }
    
    private async void do_fetch_previews(Cancellable? cancellable) throws Error {
        set_busy(true);
        Geary.NonblockingBatch batch = new Geary.NonblockingBatch();
        
        int count = main_window.message_list_store.get_count();
        for (int ctr = 0; ctr < count; ctr++) {
            Geary.Conversation? conversation;
            Geary.Email? email = main_window.message_list_store.get_email_for_preview(
                ctr, out conversation);
            
            if (email != null)
                batch.add(new FetchPreviewOperation(main_window, current_folder, email.id,
                    conversation));
        }
        
        debug("Fetching %d previews", count);
        yield batch.execute_all_async(cancellable);
        debug("Completed fetching %d previews", count);
        
        set_busy(false);
        
        batch.throw_first_exception();
        
        // with all the previews fetched, now go back and do a full list (if required)
        if (second_list_pass_required) {
            second_list_pass_required = false;
            debug("Doing second list pass now");
            current_conversations.lazy_load(-1, FETCH_EMAIL_CHUNK_COUNT, Geary.Folder.ListFlags.NONE,
                cancellable);
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
    
    private void on_conversation_selected(Geary.Conversation? conversation) {
        cancel_message();
        main_window.message_viewer.clear();
        
        current_conversation = conversation;
        
        GearyApplication.instance.actions.get_action(GearyController.ACTION_DELETE_MESSAGE).sensitive
            = (conversation != null);
        
        if (conversation != null)
            do_select_message.begin(conversation, cancellable_message, on_select_message_completed);
    }
    
    private async void do_select_message(Geary.Conversation conversation, Cancellable? 
        cancellable = null) throws Error {
        
        Gee.List<Geary.EmailIdentifier> messages = new Gee.ArrayList<Geary.EmailIdentifier>();
        if (current_folder == null) {
            debug("Conversation selected with no folder selected");
            
            return;
        }
        
        set_busy(true);
        foreach (Geary.Email email in conversation.get_pool_sorted(compare_email)) {
            Geary.Email full_email = yield current_folder.fetch_email_async(email.id,
                MessageViewer.REQUIRED_FIELDS, cancellable);
            
            if (cancellable.is_cancelled())
                break;
            
            main_window.message_viewer.add_message(full_email);
            
            if (full_email.properties.email_flags.is_unread())
                messages.add(full_email.id);
        }
        
        // Mark as read.
        if (messages.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            
            yield current_folder.mark_email_async(messages, null, flags, cancellable);
        }
    }
    
    private void on_select_message_completed(Object? source, AsyncResult result) {
        try {
            do_select_message.end(result);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                debug("Unable to select message: %s", err.message);
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
                    main_window.folder_list_store.add_user_folder(folder);
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
    
    public void debug_print_selected() {
        if (main_window.message_viewer.messages.size == 0) {
            debug("Nothing to print");
            return;
        }
        
        debug("---------------------------");
        foreach (Geary.Email e in main_window.message_viewer.messages) {
            debug("Message: %s", e.id.to_string());
            if (e.header != null)
                debug("\n%s", e.header.buffer.to_utf8());
            else
                debug("No message data.");
            
            debug("---------------------------");
        }
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
        
        old_cancellable.cancel();
    }
    
    public void on_quit() {
        GearyApplication.instance.exit();
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
    
    public void on_donate() {
        try {
            Gtk.show_uri(main_window.get_screen(), "http://yorba.org/donate/", Gdk.CURRENT_TIME);
        } catch (Error err) {
            debug("Unable to open URL. %s", err.message);
        }
    }
    
    private void on_new_message() {
        ComposerWindow w = new ComposerWindow();
        w.set_position(Gtk.WindowPosition.CENTER);
        w.send.connect(on_send);
        w.show_all();
    }
    
    private void on_delete_message() {
        // Prevent deletes of the same conversation from repeating.
        if (current_conversation == last_deleted_conversation)
            return;
        
        last_deleted_conversation = current_conversation;
        
        Gee.Set<Geary.Email>? pool = current_conversation.get_pool();
        if (pool == null)
            return;
        
        set_busy(true);
        delete_messages.begin(pool, cancellable_folder, on_delete_messages_completed);
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
    
    private void on_send(ComposerWindow cw) {
        string username;
        try {
            // TODO: Multiple accounts.
            username = Geary.Engine.get_usernames(GearyApplication.instance.get_user_data_directory())
                .get(0);
        } catch (Error e) {
            error("Unable to get username. Error: %s", e.message);
        }
        Geary.AccountInformation acct_info = account.get_account_information();
        
        Geary.ComposedEmail email = new Geary.ComposedEmail(
            new DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.single(
                new Geary.RFC822.MailboxAddress(acct_info.real_name, username)
            )
        );
        
        if (!Geary.String.is_empty(cw.to))
            email.to = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cw.to);
        
        if (!Geary.String.is_empty(cw.cc))
            email.cc = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cw.cc);
        
        if (!Geary.String.is_empty(cw.bcc))
            email.bcc = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cw.bcc);
        
        if (!Geary.String.is_empty(cw.subject))
            email.subject = new Geary.RFC822.Subject(cw.subject);
        
        email.body = new Geary.RFC822.Text(new Geary.Memory.StringBuffer(cw.message));
        
        account.send_email_async.begin(email);
        
        cw.destroy();
    }
    
    public void set_busy(bool is_busy) {
        busy_count += is_busy ? 1 : -1;
        if (busy_count < 0)
            busy_count = 0;
        
        main_window.set_busy(busy_count > 0);
    }
}

