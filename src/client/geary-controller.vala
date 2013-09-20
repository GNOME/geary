/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Primary controller object for Geary.
public class GearyController : Geary.BaseObject {
    // Named actions.
    public const string ACTION_HELP = "GearyHelp";
    public const string ACTION_ABOUT = "GearyAbout";
    public const string ACTION_DONATE = "GearyDonate";
    public const string ACTION_QUIT = "GearyQuit";
    public const string ACTION_NEW_MESSAGE = "GearyNewMessage";
    public const string ACTION_REPLY_TO_MESSAGE = "GearyReplyToMessage";
    public const string ACTION_REPLY_ALL_MESSAGE = "GearyReplyAllMessage";
    public const string ACTION_FORWARD_MESSAGE = "GearyForwardMessage";
    public const string ACTION_DELETE_MESSAGE = "GearyDeleteMessage";
    public const string ACTION_FIND_IN_CONVERSATION = "GearyFindInConversation";
    public const string ACTION_FIND_NEXT_IN_CONVERSATION = "GearyFindNextInConversation";
    public const string ACTION_FIND_PREVIOUS_IN_CONVERSATION = "GearyFindPreviousInConversation";
    public const string ACTION_ZOOM_IN = "GearyZoomIn";
    public const string ACTION_ZOOM_OUT = "GearyZoomOut";
    public const string ACTION_ZOOM_NORMAL = "GearyZoomNormal";
    public const string ACTION_ACCOUNTS = "GearyAccounts";
    public const string ACTION_PREFERENCES = "GearyPreferences";
    public const string ACTION_MARK_AS_MENU = "GearyMarkAsMenuButton";
    public const string ACTION_MARK_AS_READ = "GearyMarkAsRead";
    public const string ACTION_MARK_AS_UNREAD = "GearyMarkAsUnread";
    public const string ACTION_MARK_AS_STARRED = "GearyMarkAsStarred";
    public const string ACTION_MARK_AS_UNSTARRED = "GearyMarkAsUnStarred";
    public const string ACTION_MARK_AS_SPAM = "GearyMarkAsSpam";
    public const string ACTION_COPY_MENU = "GearyCopyMenuButton";
    public const string ACTION_MOVE_MENU = "GearyMoveMenuButton";
    public const string ACTION_GEAR_MENU = "GearyGearMenuButton";
    public const string ACTION_SEARCH = "GearySearch";
    
    public const string PROP_CURRENT_CONVERSATION ="current-conversations";
    
    public const int MIN_CONVERSATION_COUNT = 50;
    
    private const string DELETE_MESSAGE_LABEL = _("_Delete");
    private const string DELETE_MESSAGE_TOOLTIP_SINGLE = _("Delete conversation (Delete, Backspace, A)");
    private const string DELETE_MESSAGE_TOOLTIP_MULTIPLE = _("Delete conversations (Delete, Backspace, A)");
    private const string DELETE_MESSAGE_ICON_NAME = "user-trash-symbolic";
    
    private const string ARCHIVE_MESSAGE_LABEL = _("_Archive");
    private const string ARCHIVE_MESSAGE_TOOLTIP_SINGLE = _("Archive conversation (Delete, Backspace, A)");
    private const string ARCHIVE_MESSAGE_TOOLTIP_MULTIPLE = _("Archive conversations (Delete, Backspace, A)");
    private const string ARCHIVE_MESSAGE_ICON_NAME = "archive-symbolic";
    
    private const string MARK_AS_SPAM_LABEL = _("Mark as S_pam");
    private const string MARK_AS_NOT_SPAM_LABEL = _("Mark as not S_pam");
    
    private const string MARK_MESSAGE_MENU_TOOLTIP_SINGLE = _("Mark conversation");
    private const string MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE = _("Mark conversations");
    private const string LABEL_MESSAGE_TOOLTIP_SINGLE = _("Add label to conversation");
    private const string LABEL_MESSAGE_TOOLTIP_MULTIPLE = _("Add label to conversations");
    private const string MOVE_MESSAGE_TOOLTIP_SINGLE = _("Move conversation");
    private const string MOVE_MESSAGE_TOOLTIP_MULTIPLE = _("Move conversations");
    
    private const int SELECT_FOLDER_TIMEOUT_MSEC = 100;
    private const int SEARCH_TIMEOUT_MSEC = 100;
    
    private const string PROP_ATTEMPT_OPEN_ACCOUNT = "attempt-open-account";
    
    public MainWindow main_window { get; private set; }
    
    public Geary.App.ConversationMonitor? current_conversations { get; private set; default = null; }
    
    private Geary.Account? current_account = null;
    private Gee.HashMap<Geary.Account, Geary.App.EmailStore> email_stores
        = new Gee.HashMap<Geary.Account, Geary.App.EmailStore>();
    private Gee.HashMap<Geary.Account, Geary.Folder> inboxes
        = new Gee.HashMap<Geary.Account, Geary.Folder>();
    private Geary.Folder? current_folder = null;
    private Cancellable cancellable_folder = new Cancellable();
    private Cancellable cancellable_search = new Cancellable();
    private Cancellable cancellable_open_account = new Cancellable();
    private Cancellable cancellable_context_dependent_buttons = new Cancellable();
    private Gee.HashMap<Geary.Account, Cancellable> inbox_cancellables
        = new Gee.HashMap<Geary.Account, Cancellable>();
    private Gee.Set<Geary.App.Conversation> selected_conversations = new Gee.HashSet<Geary.App.Conversation>();
    private Geary.App.Conversation? last_deleted_conversation = null;
    private Gee.LinkedList<ComposerWindow> composer_windows = new Gee.LinkedList<ComposerWindow>();
    private File? last_save_directory = null;
    private NewMessagesMonitor? new_messages_monitor = null;
    private NewMessagesIndicator? new_messages_indicator = null;
    private UnityLauncher? unity_launcher = null;
    private Libnotify? libnotify = null;
    private uint select_folder_timeout_id = 0;
    private Geary.Folder? folder_to_select = null;
    private Geary.Nonblocking.Mutex select_folder_mutex = new Geary.Nonblocking.Mutex();
    private Geary.Account? account_to_select = null;
    private Geary.Folder? previous_non_search_folder = null;
    private uint search_timeout_id = 0;
    private LoginDialog? login_dialog = null;
    private UpgradeDialog upgrade_dialog;
    
    // List of windows we're waiting to close before Geary closes.
    private Gee.List<ComposerWindow> waiting_to_close = new Gee.ArrayList<ComposerWindow>();
    
    /**
     * Fired when the currently selected account has changed.
     */
    public signal void account_selected(Geary.Account? account);
    
    /**
     * Fired when the currently selected folder has changed.
     */
    public signal void folder_selected(Geary.Folder? folder);
    
    /**
     * Fired when the currently selected conversation(s) has/have changed.
     */
    public signal void conversations_selected(Gee.Set<Geary.App.Conversation>? conversations,
        Geary.Folder? current_folder);
    
    /**
     * Fired when the number of conversations changes.
     */
    public signal void conversation_count_changed(int count);
    
    /**
     * Fired when the search text is changed according to the controller.  This accounts
     * for a brief typmatic delay.
     */
    public signal void search_text_changed(string keywords);
    
    public GearyController() {
    }
    
    ~GearyController() {
        assert(current_account == null);
    }
    
    /**
     * Starts the controller and brings up Geary.
     */
    public async void open_async() {
        // This initializes the IconFactory, important to do before the actions are created (as they
        // refer to some of Geary's custom icons)
        IconFactory.instance.init();
        
        // Setup actions.
        GearyApplication.instance.actions.add_actions(create_actions(), this);
        GearyApplication.instance.actions.add_toggle_actions(create_toggle_actions(), this);
        GearyApplication.instance.ui_manager.insert_action_group(
            GearyApplication.instance.actions, 0);
        GearyApplication.instance.load_ui_file("accelerators.ui");
        
        // some actions need a little extra help
        prepare_actions();
        
        // Listen for attempts to close the application.
        GearyApplication.instance.exiting.connect(on_application_exiting);
        
        // Create DB upgrade dialog.
        upgrade_dialog = new UpgradeDialog();
        upgrade_dialog.notify[UpgradeDialog.PROP_VISIBLE_NAME].connect(display_main_window_if_ready);
        
        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow();
        main_window.notify["has-toplevel-focus"].connect(on_has_toplevel_focus);
        
        enable_message_buttons(false);
        
        Geary.Engine.instance.account_available.connect(on_account_available);
        Geary.Engine.instance.account_unavailable.connect(on_account_unavailable);
        
        // Connect to various UI signals.
        main_window.conversation_list_view.conversations_selected.connect(on_conversations_selected);
        main_window.conversation_list_view.conversation_activated.connect(on_conversation_activated);
        main_window.conversation_list_view.load_more.connect(on_load_more);
        main_window.conversation_list_view.mark_conversations.connect(on_mark_conversations);
        main_window.conversation_list_view.visible_conversations_changed.connect(on_visible_conversations_changed);
        main_window.folder_list.folder_selected.connect(on_folder_selected);
        main_window.folder_list.copy_conversation.connect(on_copy_conversation);
        main_window.folder_list.move_conversation.connect(on_move_conversation);
        main_window.main_toolbar.copy_folder_menu.folder_selected.connect(on_copy_conversation);
        main_window.main_toolbar.move_folder_menu.folder_selected.connect(on_move_conversation);
        main_window.main_toolbar.search_text_changed.connect(on_search_text_changed);
        main_window.conversation_viewer.link_selected.connect(on_link_selected);
        main_window.conversation_viewer.reply_to_message.connect(on_reply_to_message);
        main_window.conversation_viewer.reply_all_message.connect(on_reply_all_message);
        main_window.conversation_viewer.forward_message.connect(on_forward_message);
        main_window.conversation_viewer.mark_messages.connect(on_conversation_viewer_mark_messages);
        main_window.conversation_viewer.open_attachment.connect(on_open_attachment);
        main_window.conversation_viewer.save_attachments.connect(on_save_attachments);
        main_window.conversation_viewer.save_buffer_to_file.connect(on_save_buffer_to_file);
        main_window.conversation_viewer.edit_draft.connect(on_edit_draft);
        
        new_messages_monitor = new NewMessagesMonitor(should_notify_new_messages);
        main_window.folder_list.set_new_messages_monitor(new_messages_monitor);
        
        // New messages indicator (Ubuntuism)
        new_messages_indicator = NewMessagesIndicator.create(new_messages_monitor);
        new_messages_indicator.application_activated.connect(on_indicator_activated_application);
        new_messages_indicator.composer_activated.connect(on_indicator_activated_composer);
        new_messages_indicator.inbox_activated.connect(on_indicator_activated_inbox);
        
        unity_launcher = new UnityLauncher(new_messages_monitor);
        
        // libnotify
        libnotify = new Libnotify(new_messages_monitor);
        libnotify.invoked.connect(on_libnotify_invoked);
        
        // This is fired after the accounts are ready.
        Geary.Engine.instance.opened.connect(on_engine_opened);
        
        main_window.conversation_list_view.grab_focus();
        
        // Start Geary.
        try {
            yield Geary.Engine.instance.open_async(GearyApplication.instance.get_user_data_directory(), 
                GearyApplication.instance.get_resource_directory(), new SecretMediator());
            if (Geary.Engine.instance.get_accounts().size == 0) {
                create_account();
            }
        } catch (Error e) {
            error("Error opening Geary.Engine instance: %s", e.message);
        }
    }
    
    /**
     * Stops the controller and shuts down Geary.
     */
    public void close() {
        main_window.destroy();
        main_window = null;
        current_account = null;
        account_selected(null);
    }
    
    private void add_accelerator(string accelerator, string action) {
        GtkUtil.add_accelerator(GearyApplication.instance.ui_manager, GearyApplication.instance.actions,
            accelerator, action);
    }

    private Gtk.ActionEntry[] create_actions() {
        Gtk.ActionEntry[] entries = new Gtk.ActionEntry[0];
        
        Gtk.ActionEntry accounts = { ACTION_ACCOUNTS, null, TRANSLATABLE, "<Ctrl>M",
            null, on_accounts };
        accounts.label = _("A_ccounts");
        entries += accounts;
        
        Gtk.ActionEntry prefs = { ACTION_PREFERENCES, Stock._PREFERENCES, TRANSLATABLE, "<Ctrl>E",
            null, on_preferences };
        prefs.label = _("_Preferences");
        entries += prefs;

        Gtk.ActionEntry help = { ACTION_HELP, Stock._HELP, TRANSLATABLE, "F1", null, on_help };
        help.label = _("_Help");
        entries += help;

        Gtk.ActionEntry about = { ACTION_ABOUT, Stock._ABOUT, TRANSLATABLE, null, null, on_about };
        about.label = _("_About");
        entries += about;
        
        Gtk.ActionEntry donate = { ACTION_DONATE, null, TRANSLATABLE, null, null, on_donate };
        donate.label = _("_Donate");
        entries += donate;
        
        Gtk.ActionEntry quit = { ACTION_QUIT, Stock._QUIT, TRANSLATABLE, "<Ctrl>Q", null, on_quit };
        quit.label = _("_Quit");
        entries += quit;
        
        Gtk.ActionEntry mark_menu = { ACTION_MARK_AS_MENU, null, TRANSLATABLE, null, _("Mark conversation"),
            on_show_mark_menu };
        mark_menu.label = _("_Mark as...");
        mark_menu.tooltip = MARK_MESSAGE_MENU_TOOLTIP_SINGLE;
        entries += mark_menu;

        Gtk.ActionEntry mark_read = { ACTION_MARK_AS_READ, "mail-mark-read", TRANSLATABLE, "<Ctrl>I",
            null, on_mark_as_read };
        mark_read.label = _("Mark as _Read");
        entries += mark_read;
        add_accelerator("<Shift>I", ACTION_MARK_AS_READ);

        Gtk.ActionEntry mark_unread = { ACTION_MARK_AS_UNREAD, "mail-mark-unread", TRANSLATABLE,
            "<Ctrl>U", null, on_mark_as_unread };
        mark_unread.label = _("Mark as _Unread");
        entries += mark_unread;
        add_accelerator("<Shift>U", ACTION_MARK_AS_UNREAD);
        
        Gtk.ActionEntry mark_starred = { ACTION_MARK_AS_STARRED, "star-symbolic", TRANSLATABLE, "S", null,
            on_mark_as_starred };
        mark_starred.label = _("_Star");
        entries += mark_starred;

        Gtk.ActionEntry mark_unstarred = { ACTION_MARK_AS_UNSTARRED, "non-starred", TRANSLATABLE, "D",
            null, on_mark_as_unstarred };
        mark_unstarred.label = _("U_nstar");
        entries += mark_unstarred;
        
        Gtk.ActionEntry mark_spam = { ACTION_MARK_AS_SPAM, null, TRANSLATABLE, "<Ctrl>J", null,
            on_mark_as_spam };
        mark_spam.label = MARK_AS_SPAM_LABEL;
        entries += mark_spam;
        add_accelerator("exclam", ACTION_MARK_AS_SPAM); // Exclamation mark (!)
        
        Gtk.ActionEntry copy_menu = { ACTION_COPY_MENU, null, TRANSLATABLE, "L",
            _("Add label"), null };
        copy_menu.label = _("_Label");
        entries += copy_menu;

        Gtk.ActionEntry move_menu = { ACTION_MOVE_MENU, null, TRANSLATABLE, "M", _("Move conversation"), null };
        move_menu.label = _("_Move");
        entries += move_menu;

        Gtk.ActionEntry new_message = { ACTION_NEW_MESSAGE, null, null, "<Ctrl>N", 
            _("Compose new message (Ctrl+N, N)"), on_new_message };
        entries += new_message;
        add_accelerator("N", ACTION_NEW_MESSAGE);

        Gtk.ActionEntry reply_to_message = { ACTION_REPLY_TO_MESSAGE, null, _("_Reply"), "<Ctrl>R",
            _("Reply (Ctrl+R, R)"), on_reply_to_message_action };
        entries += reply_to_message;
        add_accelerator("R", ACTION_REPLY_TO_MESSAGE);
        
        Gtk.ActionEntry reply_all_message = { ACTION_REPLY_ALL_MESSAGE, null, _("R_eply All"),
            "<Ctrl><Shift>R", _("Reply all (Ctrl+Shift+R, Shift+R)"), 
            on_reply_all_message_action };
        entries += reply_all_message;
        add_accelerator("<Shift>R", ACTION_REPLY_ALL_MESSAGE);
        
        Gtk.ActionEntry forward_message = { ACTION_FORWARD_MESSAGE, null, _("_Forward"), "<Ctrl>L", 
            _("Forward (Ctrl+L, F)"), on_forward_message_action };
        entries += forward_message;
        add_accelerator("F", ACTION_FORWARD_MESSAGE);
        
        Gtk.ActionEntry find_in_conversation = { ACTION_FIND_IN_CONVERSATION, null, null, "<Ctrl>F",
        null, on_find_in_conversation_action };
        entries += find_in_conversation;
        add_accelerator("slash", ACTION_FIND_IN_CONVERSATION);
        
        Gtk.ActionEntry find_next_in_conversation = { ACTION_FIND_NEXT_IN_CONVERSATION, null, null,
            "<Ctrl>G", null, on_find_next_in_conversation_action };
        entries += find_next_in_conversation;
        
        Gtk.ActionEntry find_previous_in_conversation = { ACTION_FIND_PREVIOUS_IN_CONVERSATION,
            null, null, "<Shift><Ctrl>G", null, on_find_previous_in_conversation_action };
        entries += find_previous_in_conversation;
        
        // although this action changes according to Geary.Folder capabilities, set to Archive
        // until they're known so the "translatable" string doesn't first appear
        Gtk.ActionEntry delete_message = { ACTION_DELETE_MESSAGE, ARCHIVE_MESSAGE_ICON_NAME,
            ARCHIVE_MESSAGE_LABEL, "A", null, on_delete_message };
        delete_message.tooltip = ARCHIVE_MESSAGE_TOOLTIP_SINGLE;
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
        
        // Can't use the Action's "natural" accelerator because this Action is not tied to any
        // widget
        Gtk.ActionEntry search = { ACTION_SEARCH, null, null, null, null, on_search };
        entries += search;
        add_accelerator("<Ctrl>S", ACTION_SEARCH);
        
        return entries;
    }
    
    private Gtk.ToggleActionEntry[] create_toggle_actions() {
        Gtk.ToggleActionEntry[] entries = new Gtk.ToggleActionEntry[0];
        
        Gtk.ToggleActionEntry gear_menu = { ACTION_GEAR_MENU, null, null, "F10",
            null, null, false };
        entries += gear_menu;
        
        return entries;
    }
    
    private void prepare_actions() {
        GearyApplication.instance.get_action(ACTION_NEW_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_REPLY_TO_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_REPLY_ALL_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_FORWARD_MESSAGE).is_important = true;
        GearyApplication.instance.get_action(ACTION_DELETE_MESSAGE).is_important = true;
    }
    
    private void open_account(Geary.Account account) {
        account.report_problem.connect(on_report_problem);
        account.email_removed.connect(on_account_email_removed);
        connect_account_async.begin(account, cancellable_open_account);
    }
    
    private void close_account(Geary.Account account) {
        account.report_problem.disconnect(on_report_problem);
        account.email_removed.disconnect(on_account_email_removed);
        disconnect_account_async.begin(account);
    }
    
    private Geary.Account get_account_instance(Geary.AccountInformation account_information) {
        try {
            return Geary.Engine.instance.get_account_instance(account_information);
        } catch (Error e) {
            error("Error creating account instance: %s", e.message);
        }
    }
    
    private void on_account_available(Geary.AccountInformation account_information) {
        Geary.Account account = get_account_instance(account_information);
        
        upgrade_dialog.add_account(account, cancellable_open_account);
        open_account(account);
    }
    
    private void on_account_unavailable(Geary.AccountInformation account_information) {
        close_account(get_account_instance(account_information));
    }
    
    private void create_account() {
        Geary.AccountInformation? account_information = request_account_information(null);
        if (account_information != null)
            do_validate_until_successful_async.begin(account_information);
    }
    
    private async void do_validate_until_successful_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        Geary.AccountInformation? result = account_information;
        do {
            result = yield validate_or_retry_async(result, cancellable);
        } while (result != null);
        
        if (login_dialog != null)
            login_dialog.hide();
    }
    
    // Returns null if we are done validating, or the revised account information if we should retry.
    private async Geary.AccountInformation? validate_or_retry_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        Geary.Engine.ValidationResult result = yield validate_async(account_information,
            Geary.Engine.ValidationOption.CHECK_CONNECTIONS, cancellable);
        if (result == Geary.Engine.ValidationResult.OK)
            return null;
        
        debug("Validation failed. Prompting user for revised account information");
        Geary.AccountInformation? new_account_information =
            request_account_information(account_information, result);
        
        // If the user refused to enter account information. There is currently no way that we
        // could see this--we exit in request_account_information, and the only way that an
        // exit could be canceled is if there are unsaved composer windows open (which won't
        // happen before an account is created). However, best to include this check for the
        // future.
        if (new_account_information == null)
            return null;
        
        debug("User entered revised account information, retrying validation");
        return new_account_information;
    }
    
    // Attempts to validate and add an account.  Returns a result code indicating
    // success or one or more errors.
    public async Geary.Engine.ValidationResult validate_async(
        Geary.AccountInformation account_information, Geary.Engine.ValidationOption options,
        Cancellable? cancellable = null) {
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK;
        try {
            result = yield Geary.Engine.instance.validate_account_information_async(account_information,
                options, cancellable);
        } catch (Error err) {
            debug("Error validating account: %s", err.message);
            GearyApplication.instance.exit(-1); // Fatal error
            
            return result;
        }
        
        if (result == Geary.Engine.ValidationResult.OK) {
            Geary.AccountInformation real_account_information = account_information;
            if (account_information.is_copy()) {
                // We have a temporary copy of the account.  Find the "real" acct info object and
                // copy the new data into it.
                real_account_information = get_real_account_information(account_information);
                real_account_information.copy_from(account_information);
            }
            
            real_account_information.store_async.begin(cancellable);
            do_update_stored_passwords_async.begin(Geary.CredentialsMediator.ServiceFlag.IMAP |
                Geary.CredentialsMediator.ServiceFlag.SMTP, real_account_information);
            
            debug("Successfully validated account information");
        }
        
        return result;
    }
    
    // Returns the "real" account info associated with a copy.  If it's not a copy, null is returned.
    public Geary.AccountInformation? get_real_account_information(
        Geary.AccountInformation account_information) {
        if (account_information.is_copy()) {
            try {
                 return Geary.Engine.instance.get_accounts().get(account_information.email);
            } catch (Error e) {
                error("Account information is out of sync: %s", e.message);
            }
        }
        
        return null;
    }
    
    // Prompt the user for a service, real name, username, and password, and try to start Geary.
    private Geary.AccountInformation? request_account_information(Geary.AccountInformation? old_info,
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK) {
        Geary.AccountInformation? new_info = old_info;
        if (login_dialog == null)
            login_dialog = new LoginDialog(); // Create here so we know GTK is initialized.
        
        if (new_info != null)
            login_dialog.set_account_information(new_info, result);
        
        login_dialog.present();
        for (;;) {
            login_dialog.show_spinner(false);
            if (login_dialog.run() != Gtk.ResponseType.OK) {
                debug("User refused to enter account information. Exiting...");
                GearyApplication.instance.exit(1);
                
                return null;
            }
            
            login_dialog.show_spinner(true);
            new_info = login_dialog.get_account_information();
            
            if ((!new_info.default_imap_server_ssl && !new_info.default_imap_server_starttls)
                || (!new_info.default_smtp_server_ssl && !new_info.default_smtp_server_starttls)) {
                ConfirmationDialog security_dialog = new ConfirmationDialog(main_window,
                    _("Your settings are insecure"),
                    _("Your IMAP and/or SMTP settings do not specify SSL or TLS.  This means your username and password could be read by another person on the network.  Are you sure you want to do this?"),
                    _("Co_ntinue"));
                if (security_dialog.run() != Gtk.ResponseType.OK)
                    continue;
            }
            
            break;
        }
        
        do_update_stored_passwords_async.begin(Geary.CredentialsMediator.ServiceFlag.IMAP |
            Geary.CredentialsMediator.ServiceFlag.SMTP, new_info);
        
        return new_info;
    }
    
    private async void do_update_stored_passwords_async(Geary.CredentialsMediator.ServiceFlag services,
        Geary.AccountInformation account_information) {
        try {
            yield account_information.update_stored_passwords_async(services);
        } catch (Error e) {
            debug("Error updating stored passwords: %s", e.message);
        }
    }
    
    private void on_report_problem(Geary.Account account, Geary.Account.Problem problem, Error? err) {
        debug("Reported problem: %s Error: %s", problem.to_string(), err != null ? err.message : "(N/A)");
        
        switch (problem) {
            case Geary.Account.Problem.DATABASE_FAILURE:
            case Geary.Account.Problem.HOST_UNREACHABLE:
            case Geary.Account.Problem.NETWORK_UNAVAILABLE:
                // TODO
            break;
            
            case Geary.Account.Problem.RECV_EMAIL_LOGIN_FAILED:
            case Geary.Account.Problem.SEND_EMAIL_LOGIN_FAILED:
                // At this point, we've prompted them for the password and
                // they've hit cancel, so there's not much for us to do here.
                close_account(account);
            break;
            
            case Geary.Account.Problem.EMAIL_DELIVERY_FAILURE:
                handle_send_failure();
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    private void handle_send_failure() {
        bool activate_message = false;
        try {
            // Due to a timing hole where it's possible to delete a message
            // from the outbox after the SMTP queue has picked it up and is
            // in the process of sending it, we only want to display a message
            // telling the user there's a problem if there are any other
            // messages waiting to be sent on any account.
            foreach (Geary.AccountInformation info in Geary.Engine.instance.get_accounts().values) {
                Geary.Account account = Geary.Engine.instance.get_account_instance(info);
                if (account.is_open()) {
                    Geary.Folder? outbox = account.get_special_folder(Geary.SpecialFolderType.OUTBOX);
                    if (outbox != null && outbox.properties.email_total > 0) {
                        activate_message = true;
                        break;
                    }
                }
            }
        } catch (Error e) {
            debug("Error determining whether any outbox has messages: %s", e.message);
            activate_message = true;
        }
        
        if (activate_message) {
            if (!main_window.status_bar.is_message_active(StatusBar.Message.OUTBOX_SEND_FAILURE))
                main_window.status_bar.activate_message(StatusBar.Message.OUTBOX_SEND_FAILURE);
            libnotify.set_error_notification(_("Error sending email"),
                _("Geary encountered an error sending an email.  If the problem persists, please manually delete the email from your Outbox folder."));
        }
    }
    
    private void on_account_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        if (folder.special_folder_type == Geary.SpecialFolderType.OUTBOX) {
            main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SEND_FAILURE);
            libnotify.clear_error_notification();
        }
    }
    
    private void on_sending_started() {
        main_window.status_bar.activate_message(StatusBar.Message.OUTBOX_SENDING);
    }
    
    private void on_sending_finished() {
        main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SENDING);
    }
    
    // Removes an existing account.
    public async void remove_account_async(Geary.AccountInformation account,
        Cancellable? cancellable = null) {
        try {
            yield get_account_instance(account).close_async(cancellable);
            yield Geary.Engine.instance.remove_account_async(account, cancellable);
        } catch (Error e) {
            message("Error removing account: %s", e.message);
        }
    }
    
    public async void connect_account_async(Geary.Account account, Cancellable? cancellable = null) {
        account.folders_available_unavailable.connect(on_folders_available_unavailable);
        account.sending_monitor.start.connect(on_sending_started);
        account.sending_monitor.finish.connect(on_sending_finished);
        
        bool retry = false;
        do {
            try {
                account.set_data(PROP_ATTEMPT_OPEN_ACCOUNT, true);
                yield account.open_async(cancellable);
                retry = false;
            } catch (Error open_err) {
                debug("Unable to open account %s: %s", account.to_string(), open_err.message);
                
                if (open_err is Geary.EngineError.CORRUPT)
                    retry = yield account_database_error_async(account);
                else if (open_err is Geary.EngineError.PERMISSIONS)
                    yield account_database_perms_async(account);
                else if (open_err is Geary.EngineError.VERSION)
                    yield account_database_version_async(account);
                else
                    yield account_general_error_async(account);
                
                if (!retry)
                    return;
            }
        } while (retry);
        
        email_stores.set(account, new Geary.App.EmailStore(account));
        inbox_cancellables.set(account, new Cancellable());
        
        account.email_sent.connect(on_sent);
        
        main_window.folder_list.set_user_folders_root_name(account, _("Labels"));
        display_main_window_if_ready();
    }
    
    // Returns true if the caller should try opening the account again
    private async bool account_database_error_async(Geary.Account account) {
        bool retry = true;
        
        // give the user two options: reset the Account local store, or exit Geary.  A third
        // could be done to leave the Account in an unopened state, but we don't currently
        // have provisions for that.
        AlertDialog dialog = new QuestionDialog(main_window,
            _("Unable to open the database for %s").printf(account.information.email),
            _("There was an error opening the local mail database for this account. This is possibly due to corruption of the database file in this directory:\n\n%s\n\nGeary can rebuild the database and re-synchronize with the server or exit.\n\nRebuilding the database will destroy all local email and its attachments. <b>The mail on the your server will not be affected.</b>")
                .printf(account.information.settings_dir.get_path()),
            _("_Rebuild"), _("E_xit"));
        dialog.use_secondary_markup(true);
        switch (dialog.run()) {
            case Gtk.ResponseType.OK:
                // don't use Cancellable because we don't want to interrupt this process
                try {
                    yield account.rebuild_async();
                } catch (Error err) {
                    dialog = new ErrorDialog(main_window,
                        _("Unable to rebuild database for \"%s\"").printf(account.information.email),
                        _("Error during rebuild:\n\n%s").printf(err.message));
                    dialog.run();
                    
                    retry = false;
                }
            break;
            
            default:
                retry = false;
            break;
        }
        
        if (!retry)
            GearyApplication.instance.exit(1);
        
        return retry;
    }
    
    private async void account_database_perms_async(Geary.Account account) {
        // some other problem opening the account ... as with other flow path, can't run
        // Geary today with an account in unopened state, so have to exit
        ErrorDialog dialog = new ErrorDialog(main_window,
            _("Unable to open local mailbox for %s").printf(account.information.email),
            _("There was an error opening the local mail database for this account. This is possibly due to a file permissions problem.\n\nPlease check that you have read/write permissions for all files in this directory:\n\n%s")
                .printf(account.information.settings_dir.get_path()));
        dialog.run();
        
        GearyApplication.instance.exit(1);
    }
    
    private async void account_database_version_async(Geary.Account account) {
        ErrorDialog dialog = new ErrorDialog(main_window,
            _("Unable to open local mailbox for %s").printf(account.information.email),
            _("The version number of the local mail database is formatted for a newer version of Geary. Unfortunately, the database cannot be \"rolled back\" to work with this version of Geary.\n\nPlease install the latest version of Geary and try again."));
        dialog.run();
        
        GearyApplication.instance.exit(1);
    }
    
    private async void account_general_error_async(Geary.Account account) {
        // some other problem opening the account ... as with other flow path, can't run
        // Geary today with an account in unopened state, so have to exit
        ErrorDialog dialog = new ErrorDialog(main_window,
            _("Unable to open local mailbox for %s").printf(account.information.email),
            _("There was an error opening the local account. This is probably due to connectivity issues.\n\nPlease check your network connection and restart Geary."));
        dialog.run();
        
        GearyApplication.instance.exit(1);
    }
    
    public async void disconnect_account_async(Geary.Account account, Cancellable? cancellable = null) {
        cancel_inbox(account);
        
        previous_non_search_folder = null;
        main_window.main_toolbar.set_search_text(""); // Reset search.
        if (current_account == account) {
            cancel_folder();
            switch_to_first_inbox(); // Switch folder.
        }
        
        account.folders_available_unavailable.disconnect(on_folders_available_unavailable);
        account.sending_monitor.start.disconnect(on_sending_started);
        account.sending_monitor.finish.disconnect(on_sending_finished);
        
        if (main_window.conversation_list_store.account_owner_email == account.information.email)
            main_window.conversation_list_store.account_owner_email = null;
        main_window.folder_list.remove_account(account);
        
        if (inboxes.has_key(account)) {
            try {
                yield inboxes.get(account).close_async(cancellable);
            } catch (Error close_inbox_err) {
                debug("Unable to close monitored inbox: %s", close_inbox_err.message);
            }
            
            inboxes.unset(account);
        }
        
        try {
            yield account.close_async(cancellable);
        } catch (Error close_err) {
            debug("Unable to close account %s: %s", account.to_string(), close_err.message);
        }
        
        inbox_cancellables.unset(account);
        email_stores.unset(account);
        
        // If there are no accounts available, exit.  (This can happen if the user declines to
        // enter a password on their account.)
        try {
            if (get_num_open_accounts() == 0)
                GearyApplication.instance.exit();
        } catch (Error e) {
            message("Error enumerating accounts: %s", e.message);
        }
    }
    
    /**
     * Returns true if we've attempted to open all accounts at this point.
     */
    private bool did_attempt_open_all_accounts() {
        try {
            foreach (Geary.AccountInformation info in Geary.Engine.instance.get_accounts().values) {
                Geary.Account a = Geary.Engine.instance.get_account_instance(info);
                if (a.get_data<bool?>(PROP_ATTEMPT_OPEN_ACCOUNT) == null)
                    return false;
            }
        } catch(Error e) {
            error("Could not open accounts: %s", e.message);
        }
        
        return true;
    }
    
    /**
     * Displays the main window if we're ready.  Otherwise does nothing.
     */
    private void display_main_window_if_ready() {
        if (did_attempt_open_all_accounts() && !upgrade_dialog.visible &&
            !cancellable_open_account.is_cancelled())
            main_window.show_all();
    }
    
    /**
     * Returns the number of accounts that exist in Geary.  Note that not all accounts may be
     * open.  Zero is returned on an error.
     */
    public int get_num_accounts() {
        try {
            return Geary.Engine.instance.get_accounts().size;
        } catch (Error e) {
            debug("Error getting number of accounts: %s", e.message);
        }
        
        return 0; // on error
    }
    
    // Returns the number of open accounts.
    private int get_num_open_accounts() throws Error {
        int num = 0;
        foreach (Geary.AccountInformation info in Geary.Engine.instance.get_accounts().values) {
            Geary.Account a = Geary.Engine.instance.get_account_instance(info);
            if (a.is_open())
                num++;
        }
        
        return num;
    }
    
    // Update widgets and such to match capabilities of the current folder ... sensitivity is handled
    // by other utility methods
    private void update_ui() {
        update_tooltips();
        Gtk.Action delete_message = GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE);
        if (current_folder is Geary.FolderSupport.Archive) {
            delete_message.label = ARCHIVE_MESSAGE_LABEL;
            delete_message.icon_name = ARCHIVE_MESSAGE_ICON_NAME;
        } else {
            // even if not Geary.FolderSupportsrRemove, use delete icons and label, although they
            // may be insensitive the entire time
            delete_message.label = DELETE_MESSAGE_LABEL;
            delete_message.icon_name = DELETE_MESSAGE_ICON_NAME;
        }
    }
    
    private void on_folder_selected(Geary.Folder? folder) {
        debug("Folder %s selected", folder != null ? folder.to_string() : "(null)");
        
        // If the folder is being unset, clear the message list and exit here.
        if (folder == null) {
            current_folder = null;
            main_window.conversation_list_store.clear();
            folder_selected(null);
            
            return;
        }
        
        // To prevent the user from selecting folders too quickly, we actually
        // schedule the action to happen after a timeout instead of acting
        // directly.  If the user selects another folder during the timeout,
        // we nix the original timeout and start a new one.
        if (select_folder_timeout_id != 0)
            Source.remove(select_folder_timeout_id);
        folder_to_select = folder;
        select_folder_timeout_id = Timeout.add(SELECT_FOLDER_TIMEOUT_MSEC, on_select_folder_timeout);
    }
    
    private bool on_select_folder_timeout() {
        assert(folder_to_select != null);
        
        select_folder_timeout_id = 0;
        
        do_select_folder.begin(folder_to_select, on_select_folder_completed);
        
        folder_to_select = null;
        return false;
    }
    
    private async void do_select_folder(Geary.Folder folder) throws Error {
        if (folder == current_folder)
            return;
        
        cancel_folder();
        
        // This function is not reentrant.  It should be, because it can be
        // called reentrant-ly if you select folders quickly enough.  This
        // mutex lock is a bandaid solution to make the function safe to
        // reenter.
        int mutex_token = yield select_folder_mutex.claim_async(cancellable_folder);
        
        bool current_is_inbox = inboxes.values.contains(current_folder);
        
        Cancellable? conversation_cancellable = (current_is_inbox ?
            inbox_cancellables.get(folder.account) : cancellable_folder);
        
        // stop monitoring for conversations and close the folder (but only if not an inbox,
        // which we leave open for notifications)
        if (current_conversations != null) {
            yield current_conversations.stop_monitoring_async(!current_is_inbox, null);
            current_conversations = null;
        } else if (current_folder != null && !current_is_inbox) {
            yield current_folder.close_async();
        }
        
        if (folder != null)
            debug("switching to %s", folder.to_string());
        
        current_folder = folder;
        if (current_account != folder.account) {
            current_account = folder.account;
            account_selected(current_account);
        }
        
        folder_selected(current_folder);
        
        if (!(current_folder is Geary.SearchFolder))
            previous_non_search_folder = current_folder;
        
        main_window.conversation_list_store.set_current_folder(current_folder, conversation_cancellable);
        main_window.conversation_list_store.account_owner_email = current_account.information.email;
        
        main_window.main_toolbar.copy_folder_menu.clear();
        main_window.main_toolbar.move_folder_menu.clear();
        foreach(Geary.Folder f in current_folder.account.list_folders()) {
            main_window.main_toolbar.copy_folder_menu.add_folder(f);
            main_window.main_toolbar.move_folder_menu.add_folder(f);
        }
        
        update_ui();
        
        current_conversations = new Geary.App.ConversationMonitor(current_folder, Geary.Folder.OpenFlags.NONE,
            ConversationListStore.REQUIRED_FIELDS, MIN_CONVERSATION_COUNT);
        
        if (inboxes.values.contains(current_folder)) {
            // Inbox selected, clear new messages if visible
            clear_new_messages("do_select_folder (inbox)", null);
        }
        
        current_conversations.scan_error.connect(on_scan_error);
        current_conversations.seed_completed.connect(on_seed_completed);
        current_conversations.seed_completed.connect(on_conversation_count_changed);
        current_conversations.scan_completed.connect(on_conversation_count_changed);
        current_conversations.conversations_added.connect(on_conversation_count_changed);
        current_conversations.conversation_removed.connect(on_conversation_count_changed);
        
        if (!current_conversations.is_monitoring)
            yield current_conversations.start_monitoring_async(conversation_cancellable);
        
        select_folder_mutex.release(ref mutex_token);
    }
    
    private void on_scan_error(Error err) {
        debug("Scan error: %s", err.message);
    }
    
    private void on_seed_completed() {
        // Done scanning.  Check if we have enough messages to fill the conversation list; if not,
        // trigger a load_more();
        if (!main_window.conversation_list_has_scrollbar()) {
            debug("Not enough messages, loading more for folder %s", current_folder.to_string());
            on_load_more();
        }
    }
    
    private void on_conversation_count_changed() {
        if (current_conversations != null)
            conversation_count_changed(current_conversations.get_conversation_count());
    }
    
    private void on_libnotify_invoked(Geary.Folder? folder, Geary.Email? email) {
        new_messages_monitor.clear_all_new_messages();
        
        if (folder == null || email == null)
            return;
        
        main_window.folder_list.select_folder(folder);
        Geary.App.Conversation? conversation = current_conversations.get_conversation_for_email(email.id);
        if (conversation != null)
            main_window.conversation_list_view.select_conversation(conversation);
    }
    
    private void on_indicator_activated_application(uint32 timestamp) {
        main_window.present_with_time(timestamp);
    }
    
    private void on_indicator_activated_composer(uint32 timestamp) {
        main_window.present_with_time(timestamp);
        on_new_message();
    }
    
    private void on_indicator_activated_inbox(Geary.Folder folder, uint32 timestamp) {
        main_window.present_with_time(timestamp);
        
        main_window.folder_list.select_folder(folder);
    }
    
    private void on_load_more() {
        debug("on_load_more");
        current_conversations.min_window_count += MIN_CONVERSATION_COUNT;
    }
    
    private void on_select_folder_completed(Object? source, AsyncResult result) {
        try {
            do_select_folder.end(result);
        } catch (Error err) {
            debug("Unable to select folder: %s", err.message);
        }
    }
    
    private void on_conversations_selected(Gee.Set<Geary.App.Conversation> selected) {
        selected_conversations = selected;
        conversations_selected(selected_conversations, current_folder);
    }
    
    private void on_conversation_activated(Geary.App.Conversation activated) {
        // Currently activating a conversation is only available for drafts folders.
        if (current_folder == null || current_folder.special_folder_type !=
            Geary.SpecialFolderType.DRAFTS)
            return;
        
        // TODO: Determine how to map between conversations and drafts correctly.
        on_edit_draft(activated.get_latest_email(Geary.App.Conversation.Location.IN_FOLDER));
    }
    
    private void on_edit_draft(Geary.Email draft) {
        create_compose_window(ComposerWindow.ComposeType.NEW_MESSAGE, draft, null, true);
    }
    
    private void on_special_folder_type_changed(Geary.Folder folder, Geary.SpecialFolderType old_type,
        Geary.SpecialFolderType new_type) {
        main_window.folder_list.remove_folder(folder);
        main_window.folder_list.add_folder(folder);
    }
    
    private void on_engine_opened() {
        // Locate the first account so we can select its inbox when available.
        try {
            Gee.ArrayList<Geary.AccountInformation> all_accounts =
                new Gee.ArrayList<Geary.AccountInformation>();
            all_accounts.add_all(Geary.Engine.instance.get_accounts().values);
            if (all_accounts.size == 0) {
                debug("No accounts found.");
                return;
            }
            
            all_accounts.sort(Geary.AccountInformation.compare_ascending);
            account_to_select = Geary.Engine.instance.get_account_instance(all_accounts.get(0));
        } catch (Error e) {
            debug("Error selecting first inbox: %s", e.message);
        }
    }
    
    // Meant to be called inside the available block of on_folders_available_unavailable,
    // after we've located the first account.
    private Geary.Folder? get_initial_selection_folder(Geary.Folder folder_being_added) {
        if (folder_being_added.account == account_to_select &&
            !main_window.folder_list.is_any_selected() && inboxes.has_key(account_to_select)) {
            return inboxes.get(account_to_select);
        } else if (account_to_select == null) {
            // This is the first account being added, so select the inbox.
            return inboxes.get(folder_being_added.account);
        }
        
        return null;
    }
    
    private void on_folders_available_unavailable(Gee.Collection<Geary.Folder>? available,
        Gee.Collection<Geary.Folder>? unavailable) {
        if (available != null && available.size > 0) {
            foreach (Geary.Folder folder in available) {
                main_window.folder_list.add_folder(folder);
                if (folder.account == current_account) {
                    if (!main_window.main_toolbar.copy_folder_menu.has_folder(folder))
                        main_window.main_toolbar.copy_folder_menu.add_folder(folder);
                    if (!main_window.main_toolbar.move_folder_menu.has_folder(folder))
                        main_window.main_toolbar.move_folder_menu.add_folder(folder);
                }
                
                // monitor the Inbox for notifications
                if (folder.special_folder_type == Geary.SpecialFolderType.INBOX &&
                    !inboxes.has_key(folder.account)) {
                    inboxes.set(folder.account, folder);
                    Geary.Folder? select_folder = get_initial_selection_folder(folder);
                    
                    if (select_folder != null) {
                        // First we try to select the Inboxes branch inbox if
                        // it's there, falling back to the main folder list.
                        if (!main_window.folder_list.select_inbox(select_folder.account))
                            main_window.folder_list.select_folder(select_folder);
                    }
                    
                    folder.open_async.begin(Geary.Folder.OpenFlags.NONE, inbox_cancellables.get(folder.account));
                    
                    new_messages_monitor.add_folder(folder, inbox_cancellables.get(folder.account));
                }
                
                folder.special_folder_type_changed.connect(on_special_folder_type_changed);
            }
        }
        
        if (unavailable != null) {
            foreach (Geary.Folder folder in unavailable) {
                if (folder.special_folder_type == Geary.SpecialFolderType.INBOX &&
                    inboxes.has_key(folder.account)) {
                    new_messages_monitor.remove_folder(folder);
                }
            }
        }
    }
    
    private void cancel_folder() {
        Cancellable old_cancellable = cancellable_folder;
        cancellable_folder = new Cancellable();
        
        old_cancellable.cancel();
    }
    
    private void cancel_inbox(Geary.Account account) {
        if (!inbox_cancellables.has_key(account)) {
            debug("Unable to cancel inbox operation for %s", account.to_string());
            return;
        }
        
        Cancellable old_cancellable = inbox_cancellables.get(account);
        inbox_cancellables.set(account, new Cancellable());

        old_cancellable.cancel();
    }
    
    private void cancel_search() {
        Cancellable old_cancellable = cancellable_search;
        cancellable_search = new Cancellable();
        
        old_cancellable.cancel();
    }
    
    private void cancel_context_dependent_buttons() {
        Cancellable old_cancellable = cancellable_context_dependent_buttons;
        cancellable_context_dependent_buttons = new Cancellable();
        
        old_cancellable.cancel();
    }
    
    // We need to include the second parameter, or valac doesn't recognize the function as matching
    // YorbaApplication.exiting's signature.
    private bool on_application_exiting(YorbaApplication sender, bool panicked) {
        if (close_composition_windows())
            return true;
        
        return sender.cancel_exit();
    }
    
    private void on_quit() {
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
                Gtk.DialogFlags.DESTROY_WITH_PARENT, Stock._CLOSE, Gtk.ResponseType.CLOSE, null);
            dialog.response.connect(() => { dialog.destroy(); });
            dialog.get_content_area().add(new Gtk.Label("Error showing help: %s".printf(error.message)));
            dialog.show_all();
            dialog.run();
        }
    }

    private void on_about() {
        Gtk.show_about_dialog(main_window,
            "program-name", GearyApplication.NAME,
            "comments", GearyApplication.DESCRIPTION,
            "authors", GearyApplication.AUTHORS,
            "copyright", GearyApplication.COPYRIGHT,
            "license", GearyApplication.LICENSE,
            "version", GearyApplication.VERSION,
            "website", GearyApplication.WEBSITE,
            "website-label", GearyApplication.WEBSITE_LABEL,
            "title", _("About %s").printf(GearyApplication.NAME),
            /// Translators: add your name and email address to receive credit in the About dialog
            /// For example: Yamada Taro <yamada.taro@example.com>
            "translator-credits", _("translator-credits")
        );
    }
    
    private void on_donate() {
        try {
            Gtk.show_uri(null, GearyApplication.DONATE, Gdk.CURRENT_TIME);
        } catch (Error error) {
            debug("Error opening donate page: %s", error.message);
        }
    }
    
    // this signal does not necessarily indicate that the application previously didn't have
    // focus and now it does
    private void on_has_toplevel_focus() {
        clear_new_messages("on_has_toplevel_focus", null);
    }
    
    private void on_accounts() {
        AccountDialog.show_instance();
    }
    
    private void on_preferences() {
        PreferencesDialog.show_instance();
    }
    
    private Gee.ArrayList<Geary.EmailIdentifier> get_conversation_email_ids(
        Geary.App.Conversation conversation, bool preview_message_only,
        Gee.ArrayList<Geary.EmailIdentifier> add_to) {
        if (preview_message_only) {
            Geary.Email? preview = conversation.get_latest_email(Geary.App.Conversation.Location.ANYWHERE);
            if (preview != null)
                add_to.add(preview.id);
        } else {
            add_to.add_all(conversation.get_email_ids());
        }
        
        return add_to;
    }
    
    private Gee.Collection<Geary.EmailIdentifier> get_conversation_collection_email_ids(
        Gee.Collection<Geary.App.Conversation> conversations, bool preview_message_only = false) {
        Gee.ArrayList<Geary.EmailIdentifier> ret = new Gee.ArrayList<Geary.EmailIdentifier>();
        
        foreach(Geary.App.Conversation c in conversations)
            get_conversation_email_ids(c, preview_message_only, ret);
        
        return ret;
    }
    
    private Gee.ArrayList<Geary.EmailIdentifier> get_selected_email_ids(
        bool preview_messages_only) {
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.App.Conversation conversation in selected_conversations)
            get_conversation_email_ids(conversation, preview_messages_only, ids);
        return ids;
    }
    
    private void mark_email(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove) {
        if (ids.size > 0) {
            email_stores.get(current_folder.account).mark_email_async.begin(
                ids, flags_to_add, flags_to_remove, cancellable_folder);
        }
    }
    
    private void on_show_mark_menu() {
        bool unread_selected = false;
        bool read_selected = false;
        bool starred_selected = false;
        bool unstarred_selected = false;
        foreach (Geary.App.Conversation conversation in selected_conversations) {
            if (conversation.is_unread())
                unread_selected = true;
            if (conversation.has_any_read_message())
                read_selected = true;

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
        
        Geary.Folder? spam_folder = null;
        try {
            spam_folder = current_account.get_special_folder(Geary.SpecialFolderType.SPAM);
        } catch (Error e) {
            debug("Could not locate special spam folder: %s", e.message);
        }
        
        if (spam_folder != null &&
            current_folder.special_folder_type != Geary.SpecialFolderType.DRAFTS &&
            current_folder.special_folder_type != Geary.SpecialFolderType.OUTBOX) {
            if (current_folder.special_folder_type == Geary.SpecialFolderType.SPAM) {
                // We're in the spam folder.
                actions.get_action(ACTION_MARK_AS_SPAM).sensitive = true;
                actions.get_action(ACTION_MARK_AS_SPAM).label = MARK_AS_NOT_SPAM_LABEL;
            } else {
                // We're not in the spam folder, but we are in a folder that allows mark-as-spam.
                actions.get_action(ACTION_MARK_AS_SPAM).sensitive = true;
                actions.get_action(ACTION_MARK_AS_SPAM).label = MARK_AS_SPAM_LABEL;
            }
        } else {
            // No Spam folder, or we're in Drafts/Outbox, so gray-out the option.
            actions.get_action(ACTION_MARK_AS_SPAM).sensitive = false;
            actions.get_action(ACTION_MARK_AS_SPAM).label = MARK_AS_SPAM_LABEL;
        }
    }
    
    private void on_visible_conversations_changed(Gee.Set<Geary.App.Conversation> visible) {
        clear_new_messages("on_visible_conversations_changed", visible);
    }
    
    private bool should_notify_new_messages(Geary.Folder folder) {
        // A monitored folder must be selected to squelch notifications;
        // if conversation list is at top of display, don't display
        // and don't display if main window has top-level focus
        return folder != current_folder
            || main_window.conversation_list_view.vadjustment.value != 0.0
            || !main_window.has_toplevel_focus;
    }
    
    // Clears messages if conditions are true: anything in should_notify_new_messages() is
    // false and the supplied visible messages are visible in the conversation list view
    private void clear_new_messages(string caller, Gee.Set<Geary.App.Conversation>? supplied) {
        if (current_folder == null || !new_messages_monitor.get_folders().contains(current_folder)
            || should_notify_new_messages(current_folder))
            return;
        
        Gee.Set<Geary.App.Conversation> visible =
            supplied ?? main_window.conversation_list_view.get_visible_conversations();
        
        foreach (Geary.App.Conversation conversation in visible) {
            if (new_messages_monitor.are_any_new_messages(current_folder, conversation.get_email_ids())) {
                debug("Clearing new messages: %s", caller);
                new_messages_monitor.clear_new_messages(current_folder);
                
                break;
            }
        }
    }
    
    private void on_mark_conversations(Gee.Collection<Geary.App.Conversation> conversations,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove,
        bool only_mark_preview = false) {
        mark_email(get_conversation_collection_email_ids(conversations, only_mark_preview),
            flags_to_add, flags_to_remove);
    }
    
    private void on_conversation_viewer_mark_messages(Gee.Collection<Geary.EmailIdentifier> emails,
        Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove) {
        mark_email(emails, flags_to_add, flags_to_remove);
    }
    
    private void on_mark_as_read() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        
        Gee.ArrayList<Geary.EmailIdentifier> ids = get_selected_email_ids(false);
        mark_email(ids, null, flags);
        
        foreach (Geary.EmailIdentifier id in ids)
            main_window.conversation_viewer.mark_manual_read(id);
    }

    private void on_mark_as_unread() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        
        Gee.ArrayList<Geary.EmailIdentifier> ids = get_selected_email_ids(false);
        mark_email(ids, flags, null);
        
        foreach (Geary.EmailIdentifier id in ids)
            main_window.conversation_viewer.mark_manual_read(id);
    }

    private void on_mark_as_starred() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_email(get_selected_email_ids(true), flags, null);
    }

    private void on_mark_as_unstarred() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_email(get_selected_email_ids(false), null, flags);
    }
    
    private void on_mark_as_spam() {
        Geary.Folder? destination_folder = null;
        if (current_folder.special_folder_type != Geary.SpecialFolderType.SPAM) {
            // Move to spam folder.
            try {
                destination_folder = current_account.get_special_folder(Geary.SpecialFolderType.SPAM);
            } catch (Error e) {
                debug("Error getting spam folder: %s", e.message);
            }
        } else {
            // Move out of spam folder, back to inbox.
            try {
                destination_folder = current_account.get_special_folder(Geary.SpecialFolderType.INBOX);
            } catch (Error e) {
                debug("Error getting inbox folder: %s", e.message);
            }
        }
        
        if (destination_folder != null)
            on_move_conversation(destination_folder);
    }
    
    private void copy_email(Gee.Collection<Geary.EmailIdentifier> ids,
        Geary.FolderPath destination) {
        if (ids.size > 0) {
            email_stores.get(current_folder.account).copy_email_async.begin(
                ids, destination, cancellable_folder);
        }
    }
    
    private void on_copy_conversation(Geary.Folder destination) {
        copy_email(get_selected_email_ids(false), destination.path);
    }
    
    private void on_move_conversation(Geary.Folder destination) {
        // Nothing to do if nothing selected.
        if (selected_conversations == null || selected_conversations.size == 0)
            return;
        
        Gee.List<Geary.EmailIdentifier> ids = get_selected_email_ids(false);
        if (ids.size == 0)
            return;
        
        Geary.FolderSupport.Move? supports_move = current_folder as Geary.FolderSupport.Move;
        if (supports_move == null)
            return;
        
        supports_move.move_email_async.begin(ids, destination.path, cancellable_folder);
    }
    
    private void on_open_attachment(Geary.Attachment attachment) {
        if (GearyApplication.instance.config.ask_open_attachment) {
            QuestionDialog ask_to_open = new QuestionDialog.with_checkbox(main_window,
                _("Are you sure you want to open \"%s\"?").printf(attachment.file.get_basename()),
                _("Attachments may cause damage to your system if opened.  Only open files from trusted sources."),
                Stock._OPEN_BUTTON, Stock._CANCEL, _("Don't _ask me again"), false);
            if (ask_to_open.run() != Gtk.ResponseType.OK)
                return;
            
            // only save checkbox state if OK was selected
            GearyApplication.instance.config.ask_open_attachment = !ask_to_open.is_checked;
        }
        
        open_uri(attachment.file.get_uri());
    }
    
    private bool do_overwrite_confirmation(File to_overwrite) {
        string primary = _("A file named \"%s\" already exists.  Do you want to replace it?").printf(
            to_overwrite.get_basename());
        string secondary = _("The file already exists in \"%s\".  Replacing it will overwrite its contents.").printf(
            to_overwrite.get_parent().get_basename());
        
        ConfirmationDialog dialog = new ConfirmationDialog(main_window, primary, secondary, _("_Replace"));
        
        return (dialog.run() == Gtk.ResponseType.OK);
    }
    
    private Gtk.FileChooserConfirmation on_confirm_overwrite(Gtk.FileChooser chooser) {
        // this is only called when choosing one file
        return do_overwrite_confirmation(chooser.get_file()) ? Gtk.FileChooserConfirmation.ACCEPT_FILENAME
            : Gtk.FileChooserConfirmation.SELECT_AGAIN;
    }
    
    private void on_save_attachments(Gee.List<Geary.Attachment> attachments) {
        if (attachments.size == 0)
            return;
        
        Gtk.FileChooserAction action = (attachments.size == 1)
            ? Gtk.FileChooserAction.SAVE
            : Gtk.FileChooserAction.SELECT_FOLDER;
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(null, main_window, action,
            Stock._CANCEL, Gtk.ResponseType.CANCEL, Stock._SAVE, Gtk.ResponseType.ACCEPT, null);
        if (last_save_directory != null)
            dialog.set_current_folder(last_save_directory.get_path());
        if (attachments.size == 1) {
            dialog.set_current_name(attachments[0].file.get_basename());
            dialog.set_do_overwrite_confirmation(true);
            // use custom overwrite confirmation so it looks consistent whether one or many
            // attachments are being saved
            dialog.confirm_overwrite.connect(on_confirm_overwrite);
        }
        dialog.set_create_folders(true);
        dialog.set_local_only(false);
        
        bool accepted = (dialog.run() == Gtk.ResponseType.ACCEPT);
        File destination = File.new_for_path(dialog.get_filename());
        
        dialog.destroy();
        
        if (!accepted)
            return;
        
        // Proceeding, save this as last destination directory
        last_save_directory = (attachments.size == 1) ? destination.get_parent() : destination;
        
        debug("Saving attachments to %s", destination.get_path());
        
        // Save each one, checking for overwrite only if multiple attachments are being written
        foreach (Geary.Attachment attachment in attachments) {
            File source_file = attachment.file;
            File dest_file = (attachments.size == 1) ? destination : destination.get_child(attachment.file.get_basename());
            
            if (attachments.size > 1 && dest_file.query_exists() && !do_overwrite_confirmation(dest_file))
                return;
            
            debug("Copying %s to %s...", source_file.get_path(), dest_file.get_path());
            
            source_file.copy_async.begin(dest_file, FileCopyFlags.OVERWRITE, Priority.DEFAULT, null,
                null, on_save_completed);
        }
    }
    
    private void on_save_completed(Object? source, AsyncResult result) {
        try {
            ((File) source).copy_async.end(result);
        } catch (Error error) {
            message("Failed to copy attachment %s to destination: %s", ((File) source).get_path(),
                error.message);
        }
    }
    
    private void on_save_buffer_to_file(string? filename, Geary.Memory.Buffer buffer) {
        Gtk.FileChooserDialog dialog = new Gtk.FileChooserDialog(null, main_window, Gtk.FileChooserAction.SAVE,
            Stock._CANCEL, Gtk.ResponseType.CANCEL, Stock._SAVE, Gtk.ResponseType.ACCEPT, null);
        if (last_save_directory != null)
            dialog.set_current_folder(last_save_directory.get_path());
        if (!Geary.String.is_empty(filename))
            dialog.set_current_name(filename);
        dialog.set_do_overwrite_confirmation(true);
        dialog.confirm_overwrite.connect(on_confirm_overwrite);
        dialog.set_create_folders(true);
        dialog.set_local_only(false);
        
        bool accepted = (dialog.run() == Gtk.ResponseType.ACCEPT);
        string? accepted_filename = dialog.get_filename();
        
        dialog.destroy();
        
        if (!accepted || Geary.String.is_empty(accepted_filename))
            return;
        
        File destination = File.new_for_path(accepted_filename);
        
        // Proceeding, save this as last destination directory
        last_save_directory = destination.get_parent();
        
        debug("Saving buffer to %s", destination.get_path());
        
        // Create the file where the image will be saved and get the output stream.
        try {
            FileOutputStream outs = destination.replace(null, false, FileCreateFlags.REPLACE_DESTINATION,
                null);
            outs.splice_async.begin(buffer.get_input_stream(),
                OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET,
                Priority.DEFAULT, null, on_save_buffer_to_file_completed);
        } catch (Error err) {
            message("Unable to save buffer to \"%s\": %s", filename, err.message);
        }
    }
    
    private void on_save_buffer_to_file_completed(Object? source, AsyncResult result) {
        try {
            ((FileOutputStream) source).splice_async.end(result);
        } catch (Error err) {
            message("Failed to save buffer to file: %s", err.message);
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
        Gee.List<ComposerWindow> composers_to_destroy = new Gee.ArrayList<ComposerWindow>();
        bool quit_cancelled = false;
        
        // If there's composer windows open, give the user a chance to save or cancel.
        foreach(ComposerWindow cw in composer_windows) {
            // Check if we should close the window immediately, or if we need to wait.
            if (!cw.should_close()) {
                if (cw.delayed_close) {
                    // Window is currently busy saving.
                    waiting_to_close.add(cw);
                    
                    continue;
                } else {
                    // User cancelled operation.
                    quit_cancelled = true;
                    
                    break;
                }
            }
            
            // Hide any existing composer windows for the moment; actually deleting the windows
            // will result in their removal from composer_windows, which could crash this loop.
            composers_to_destroy.add(cw);
            cw.hide();
        }
        
        // Safely destroy windows.
        foreach(ComposerWindow cw in composers_to_destroy)
            cw.destroy();
        
        // If we cancelled the quit we can bail here.
        if (quit_cancelled) {
            waiting_to_close.clear();
            
            return false;
        }
        
        // If there's still windows saving, we can't exit just yet.  Hide the main window and wait.
        if (waiting_to_close.size > 0) {
            main_window.hide();
            
            return false;
        }
        
        // If we deleted all composer windows without the user cancelling, we can exit.
        return true;
    }
    
    private void create_compose_window(ComposerWindow.ComposeType compose_type,
        Geary.Email? referred = null, string? mailto = null, bool is_draft = false) {
        create_compose_window_async.begin(compose_type, referred, mailto, is_draft);
    }
    
    private async void create_compose_window_async(ComposerWindow.ComposeType compose_type,
        Geary.Email? referred = null, string? mailto = null, bool is_draft = false) {
        if (current_account == null)
            return;
        
        ComposerWindow window;
        if (mailto != null) {
            window = new ComposerWindow.from_mailto(current_account, mailto);
        } else {
            Geary.Email? full = null;
            if (referred != null) {
                try {
                    full = yield email_stores.get(current_folder.account).fetch_email_async(
                        referred.id, Geary.ComposedEmail.REQUIRED_REPLY_FIELDS,
                        Geary.Folder.ListFlags.NONE, cancellable_folder);
                } catch (Error e) {
                    message("Could not load full message: %s", e.message);
                }
            }
            
            window = new ComposerWindow(current_account, compose_type, full, is_draft);
        }
        window.set_position(Gtk.WindowPosition.CENTER);
        
        // We want to keep track of the open composer windows, so we can allow the user to cancel
        // an exit without losing their data.
        composer_windows.add(window);
        window.destroy.connect(on_composer_window_destroy);
        
        window.show_all();
    }
    
    private void on_composer_window_destroy(Gtk.Widget sender) {
        composer_windows.remove((ComposerWindow) sender);
        
        if (waiting_to_close.remove((ComposerWindow) sender)) {
            // If we just removed the last window in the waiting to close list, it's time to exit!
            if (waiting_to_close.size == 0)
                GearyApplication.instance.exit();
        }
    }
    
    private void on_new_message() {
        create_compose_window(ComposerWindow.ComposeType.NEW_MESSAGE);
    }
    
    private void on_reply_to_message(Geary.Email message) {
        create_compose_window(ComposerWindow.ComposeType.REPLY, message);
    }
    
    private void on_reply_to_message_action() {
        Geary.Email? message = main_window.conversation_viewer.get_last_message();
        if (message != null)
            on_reply_to_message(message);
    }
    
    private void on_reply_all_message(Geary.Email message) {
        create_compose_window(ComposerWindow.ComposeType.REPLY_ALL, message);
    }
    
    private void on_reply_all_message_action() {
        Geary.Email? message = main_window.conversation_viewer.get_last_message();
        if (message != null)
            on_reply_all_message(message);
    }
    
    private void on_forward_message(Geary.Email message) {
        create_compose_window(ComposerWindow.ComposeType.FORWARD, message);
    }
    
    private void on_forward_message_action() {
        Geary.Email? message = main_window.conversation_viewer.get_last_message();
        if (message != null)
            on_forward_message(message);
    }
    
    private void on_find_in_conversation_action() {
        main_window.conversation_viewer.show_find_bar();
    }
    
    private void on_find_next_in_conversation_action() {
        main_window.conversation_viewer.find(true);
    }
    
    private void on_find_previous_in_conversation_action() {
        main_window.conversation_viewer.find(false);
    }
    
    // This method is used for both removing and archive a message; currently Geary only supports
    // one or the other in a folder
    private void on_delete_message() {
        // Prevent deletes of the same conversation from repeating.
        if (main_window.conversation_viewer.current_conversation != null
            && main_window.conversation_viewer.current_conversation == last_deleted_conversation) {
            debug("not archiving/deleting, viewed conversation is last deleted conversation");
            
            return;
        }
        
        // There should always be at least one conversation selected here, otherwise the archive
        // button is disabled, but better safe than segfaulted.
        last_deleted_conversation = selected_conversations.size > 0
            ? Geary.Collection.get_first<Geary.App.Conversation>(selected_conversations) : null;
        
        // If the user clicked the toolbar button, we want to move focus back to the message list.
        main_window.conversation_list_view.grab_focus();
        
        delete_messages.begin(get_selected_email_ids(false), cancellable_folder, on_delete_messages_completed);
    }
    
    // This method is used for both removing and archive a message; currently Geary only supports
    // one or the other in a folder.  This will try archiving first, then remove.
    private async void delete_messages(Gee.List<Geary.EmailIdentifier> ids, Cancellable? cancellable)
        throws Error {
        Geary.FolderSupport.Archive? supports_archive = current_folder as Geary.FolderSupport.Archive;
        if (supports_archive != null) {
            yield supports_archive.archive_email_async(ids, cancellable);
            
            return;
        }
        
        Geary.FolderSupport.Remove? supports_remove = current_folder as Geary.FolderSupport.Remove;
        if (supports_remove != null) {
            yield supports_remove.remove_email_async(ids, cancellable);
            
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
    }
    
    private void on_zoom_in() {
        main_window.conversation_viewer.web_view.zoom_in();
    }

    private void on_zoom_out() {
        main_window.conversation_viewer.web_view.zoom_out();
    }

    private void on_zoom_normal() {
        main_window.conversation_viewer.web_view.zoom_level = 1.0f;
    }
    
    private void on_search() {
        main_window.main_toolbar.give_search_focus();
    }
    
    private void on_sent(Geary.RFC822.Message rfc822) {
        Libnotify.play_sound("message-sent-email");
    }
    
    private void on_link_selected(string link) {
        if (link.down().has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            compose_mailto(link);
        } else {
            open_uri(link);
        }
    }

    // Disables all single-message buttons and enables all multi-message buttons.
    public void enable_multiple_message_buttons() {
        update_tooltips();
        
        // Single message only buttons.
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = false;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = false;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = false;

        // Mutliple message buttons.
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).sensitive =
            (current_folder is Geary.FolderSupport.Move);
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive =
            (current_folder is Geary.FolderSupport.Remove) || (current_folder is Geary.FolderSupport.Archive);
        
        cancel_context_dependent_buttons();
        enable_context_dependent_buttons_async.begin(true, cancellable_context_dependent_buttons);
    }

    // Enables or disables the message buttons on the toolbar.
    public void enable_message_buttons(bool sensitive) {
        update_tooltips();
        
        // No reply/forward in drafts folder.
        bool respond_sensitive = sensitive;
        if (current_folder != null && current_folder.special_folder_type == Geary.SpecialFolderType.DRAFTS)
            respond_sensitive = false;
        
        GearyApplication.instance.actions.get_action(ACTION_REPLY_TO_MESSAGE).sensitive = respond_sensitive;
        GearyApplication.instance.actions.get_action(ACTION_REPLY_ALL_MESSAGE).sensitive = respond_sensitive;
        GearyApplication.instance.actions.get_action(ACTION_FORWARD_MESSAGE).sensitive = respond_sensitive;
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).sensitive =
            sensitive && (current_folder is Geary.FolderSupport.Move);
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive = sensitive
            && ((current_folder is Geary.FolderSupport.Remove) || (current_folder is Geary.FolderSupport.Archive));
        
        cancel_context_dependent_buttons();
        enable_context_dependent_buttons_async.begin(sensitive, cancellable_context_dependent_buttons);
    }
    
    private async void enable_context_dependent_buttons_async(bool sensitive, Cancellable? cancellable) {
        Gee.MultiMap<Geary.EmailIdentifier, Type>? selected_operations = null;
        try {
            if (current_folder != null) {
                selected_operations = yield email_stores.get(current_folder.account)
                    .get_supported_operations_async(get_selected_email_ids(false), cancellable);
            }
        } catch (Error e) {
            debug("Error checking for what operations are supported in the selected conversations: %s",
                e.message);
        }
        
        // Exit here if the user has cancelled.
        if (cancellable != null && cancellable.is_cancelled())
            return;
        
        Gee.HashSet<Type> supported_operations = new Gee.HashSet<Type>();
        if (selected_operations != null)
            supported_operations.add_all(selected_operations.get_values());
        
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).sensitive =
            sensitive && (supported_operations.contains(typeof(Geary.FolderSupport.Mark)));
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).sensitive =
            sensitive && (supported_operations.contains(typeof(Geary.FolderSupport.Copy)));
    }
    
    // Updates tooltip text depending on number of conversations selected.
    private void update_tooltips() {
        bool single = selected_conversations.size == 1;
        
        GearyApplication.instance.actions.get_action(ACTION_MARK_AS_MENU).tooltip = single ?
            MARK_MESSAGE_MENU_TOOLTIP_SINGLE : MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE;
        GearyApplication.instance.actions.get_action(ACTION_COPY_MENU).tooltip = single ?
            LABEL_MESSAGE_TOOLTIP_SINGLE : LABEL_MESSAGE_TOOLTIP_MULTIPLE;
        GearyApplication.instance.actions.get_action(ACTION_MOVE_MENU).tooltip = single ?
            MOVE_MESSAGE_TOOLTIP_SINGLE : MOVE_MESSAGE_TOOLTIP_MULTIPLE;
        
        if (current_folder is Geary.FolderSupport.Archive) {
            GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).tooltip = single ?
                ARCHIVE_MESSAGE_TOOLTIP_SINGLE : ARCHIVE_MESSAGE_TOOLTIP_MULTIPLE;
        } else {
            GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).tooltip = single ?
                DELETE_MESSAGE_TOOLTIP_SINGLE : DELETE_MESSAGE_TOOLTIP_MULTIPLE;
        }
    }
    
    public void compose_mailto(string mailto) {
        create_compose_window(ComposerWindow.ComposeType.NEW_MESSAGE, null, mailto);
    }
    
    // Returns a list of composer windows for an account, or null if none.
    public Gee.List<ComposerWindow>? get_composer_windows_for_account(Geary.AccountInformation account) {
        Gee.List<ComposerWindow> ret = new Gee.LinkedList<ComposerWindow>();
        foreach (ComposerWindow cw in composer_windows) {
            if (cw.account.information == account)
                ret.add(cw);
        }
        
        return ret.size >= 1 ? ret : null;
    }
    
    private void do_search(string search_text) {
        Geary.SearchFolder? folder = null;
        try {
            folder = (Geary.SearchFolder) current_account.get_special_folder(
                Geary.SpecialFolderType.SEARCH);
        } catch (Error e) {
            debug("Could not get search folder: %s", e.message);
            
            return;
        }
        
        if (search_text == "") {
            if (previous_non_search_folder != null && current_folder is Geary.SearchFolder)
                main_window.folder_list.select_folder(previous_non_search_folder);
            
            main_window.folder_list.remove_search();
            search_text_changed("");
            folder.clear();
            
            return;
        }
        
        if (current_account == null)
            return;
        
        cancel_search(); // Stop any search in progress.
        
        folder.set_search_query(search_text, cancellable_search);
        
        main_window.folder_list.set_search(folder);
        search_text_changed(main_window.main_toolbar.search_text);
    }
    
    private void on_search_text_changed(string search_text) {
        // So we don't thrash the disk as the user types, we run the actual
        // search after a quick delay when they finish typing.
        if (search_timeout_id != 0)
            Source.remove(search_timeout_id);
        search_timeout_id = Timeout.add(SEARCH_TIMEOUT_MSEC, on_search_timeout);
    }
    
    private bool on_search_timeout() {
        search_timeout_id = 0;
        
        do_search(main_window.main_toolbar.search_text);
        
        return false;
    }
    
    /**
     * Returns a read-only set of currently selected conversations.
     */
    public Gee.Set<Geary.App.Conversation> get_selected_conversations() {
        return selected_conversations.read_only_view;
    }
    
    // Find the first inbox we know about and switch to it.
    private void switch_to_first_inbox() {
        try {
            if (Geary.Engine.instance.get_accounts().values.size == 0)
                return; // No account!
            
            // Look through our accounts, grab the first inbox we can find.
            Geary.Folder? first_inbox = null;
            
            foreach(Geary.AccountInformation info in Geary.Engine.instance.get_accounts().values) {
                first_inbox = get_account_instance(info).get_special_folder(Geary.SpecialFolderType.INBOX);
                
                if (first_inbox != null)
                    break;
            }
            
            if (first_inbox == null)
                return;
            
            // Attempt the selection.  Try the inboxes branch first.
            if (!main_window.folder_list.select_inbox(first_inbox.account))
                main_window.folder_list.select_folder(first_inbox);
        } catch (Error e) {
            debug("Could not locate inbox: %s", e.message);
        }
    }
}

