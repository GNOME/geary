/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Required because Gcr's VAPI is behind-the-times
// TODO: When bindings available, use async variants of these calls
extern const string GCR_PURPOSE_SERVER_AUTH;
extern bool gcr_trust_add_pinned_certificate(Gcr.Certificate cert, string purpose, string peer,
    Cancellable? cancellable) throws Error;
extern bool gcr_trust_is_certificate_pinned(Gcr.Certificate cert, string purpose, string peer,
    Cancellable? cancellable) throws Error;
extern bool gcr_trust_remove_pinned_certificate(Gcr.Certificate cert, string purpose, string peer,
    Cancellable? cancellable) throws Error;

// Primary controller object for Geary.
public class GearyController : Geary.BaseObject {
    // Named actions.
    //
    // NOTE: Some actions with accelerators need to also be added to ui/accelerators.ui
    public const string ACTION_HELP = "GearyHelp";
    public const string ACTION_ABOUT = "GearyAbout";
    public const string ACTION_DONATE = "GearyDonate";
    public const string ACTION_QUIT = "GearyQuit";
    public const string ACTION_NEW_MESSAGE = "GearyNewMessage";
    public const string ACTION_REPLY_TO_MESSAGE = "GearyReplyToMessage";
    public const string ACTION_REPLY_ALL_MESSAGE = "GearyReplyAllMessage";
    public const string ACTION_FORWARD_MESSAGE = "GearyForwardMessage";
    public const string ACTION_ARCHIVE_MESSAGE = "GearyArchiveMessage";
    public const string ACTION_TRASH_MESSAGE = "GearyTrashMessage";
    public const string ACTION_DELETE_MESSAGE = "GearyDeleteMessage";
    public const string ACTION_EMPTY_MENU = "GearyEmptyMenu";
    public const string ACTION_EMPTY_SPAM = "GearyEmptySpam";
    public const string ACTION_EMPTY_TRASH = "GearyEmptyTrash";
    public const string ACTION_UNDO = "GearyUndo";
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
    
    private const string DELETE_MESSAGE_TOOLTIP_SINGLE = _("Delete conversation (Shift+Delete)");
    private const string DELETE_MESSAGE_TOOLTIP_MULTIPLE = _("Delete conversations (Shift+Delete)");
    private const string DELETE_MESSAGE_ICON_NAME = "edit-delete-symbolic";
    
    // This refers to the action ("move email to the trash"), not the Trash folder itself
    private const string TRASH_MESSAGE_TOOLTIP_SINGLE = _("Move conversation to Trash (Delete, Backspace)");
    private const string TRASH_MESSAGE_TOOLTIP_MULTIPLE = _("Move conversations to Trash (Delete, Backspace)");
    private const string TRASH_MESSAGE_ICON_NAME = "user-trash-symbolic";
    
    // This refers to the action ("archive an email"), not the Archive folder itself
    private const string ARCHIVE_MESSAGE_LABEL = _("_Archive");
    private const string ARCHIVE_MESSAGE_TOOLTIP_SINGLE = _("Archive conversation (A)");
    private const string ARCHIVE_MESSAGE_TOOLTIP_MULTIPLE = _("Archive conversations (A)");
    private const string ARCHIVE_MESSAGE_ICON_NAME = "mail-archive-symbolic";
    
    private const string MARK_AS_SPAM_LABEL = _("Mark as S_pam");
    private const string MARK_AS_NOT_SPAM_LABEL = _("Mark as not S_pam");
    
    private const string MARK_MESSAGE_MENU_TOOLTIP_SINGLE = _("Mark conversation");
    private const string MARK_MESSAGE_MENU_TOOLTIP_MULTIPLE = _("Mark conversations");
    private const string LABEL_MESSAGE_TOOLTIP_SINGLE = _("Add label to conversation");
    private const string LABEL_MESSAGE_TOOLTIP_MULTIPLE = _("Add label to conversations");
    private const string MOVE_MESSAGE_TOOLTIP_SINGLE = _("Move conversation");
    private const string MOVE_MESSAGE_TOOLTIP_MULTIPLE = _("Move conversations");
    
    private const int SELECT_FOLDER_TIMEOUT_USEC = 100 * 1000;
    private const int SEARCH_TIMEOUT_MSEC = 250;
    
    private const string PROP_ATTEMPT_OPEN_ACCOUNT = "attempt-open-account";
    
    public MainWindow main_window { get; private set; }
    
    public Geary.App.ConversationMonitor? current_conversations { get; private set; default = null; }
    
    public AutostartManager? autostart_manager { get; private set; default = null; }
    
    public LoginDialog? login_dialog { get; private set; default = null; }
    
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
    private Gee.LinkedList<ComposerWidget> composer_widgets = new Gee.LinkedList<ComposerWidget>();
    private File? last_save_directory = null;
    private NewMessagesMonitor? new_messages_monitor = null;
    private NewMessagesIndicator? new_messages_indicator = null;
    private UnityLauncher? unity_launcher = null;
    private Libnotify? libnotify = null;
    private uint select_folder_timeout_id = 0;
    private int64 next_folder_select_allowed_usec = 0;
    private Geary.Folder? folder_to_select = null;
    private Geary.Nonblocking.Mutex select_folder_mutex = new Geary.Nonblocking.Mutex();
    private Geary.Account? account_to_select = null;
    private Geary.Folder? previous_non_search_folder = null;
    private uint search_timeout_id = 0;
    private UpgradeDialog upgrade_dialog;
    private Gee.List<string> pending_mailtos = new Gee.ArrayList<string>();
    private Geary.Nonblocking.Mutex untrusted_host_prompt_mutex = new Geary.Nonblocking.Mutex();
    private Gee.HashSet<Geary.Endpoint> validating_endpoints = new Gee.HashSet<Geary.Endpoint>();
    private Geary.Revokable? revokable = null;
    
    // List of windows we're waiting to close before Geary closes.
    private Gee.List<ComposerWidget> waiting_to_close = new Gee.ArrayList<ComposerWidget>();
    
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
        setup_actions();
        GearyApplication.instance.load_ui_file("accelerators.ui");
        
        // Listen for attempts to close the application.
        GearyApplication.instance.exiting.connect(on_application_exiting);
        
        // Create DB upgrade dialog.
        upgrade_dialog = new UpgradeDialog();
        upgrade_dialog.notify[UpgradeDialog.PROP_VISIBLE_NAME].connect(display_main_window_if_ready);
        
        // Create the main window (must be done after creating actions.)
        main_window = new MainWindow(GearyApplication.instance);
        main_window.on_shift_key.connect(on_shift_key);
        main_window.notify["has-toplevel-focus"].connect(on_has_toplevel_focus);
        
        enable_message_buttons(false);
        
        Geary.Engine.instance.account_available.connect(on_account_available);
        Geary.Engine.instance.account_unavailable.connect(on_account_unavailable);
        Geary.Engine.instance.untrusted_host.connect(on_untrusted_host);
        
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
        
        // instantiate here to ensure that Config is initialized and ready
        autostart_manager = new AutostartManager();
        
        // initialize revokable
        save_revokable(null, null);
        
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
     * At the moment, this is non-reversible, i.e. once closed a GearyController cannot be
     * re-opened.
     */
    public async void close_async() {
        // hide window while shutting down, as this can take a few seconds under certain conditions
        main_window.hide();
        
        // drop the Revokable, which will commit it if necessary
        save_revokable(null, null);
        
        // close the ConversationMonitor
        try {
            if (current_conversations != null) {
                debug("Stopping conversation monitor for %s...", current_conversations.folder.to_string());
                
                bool closing = yield current_conversations.stop_monitoring_async(null);
                
                // If not an Inbox, wait for it to close so all pending operations are flushed
                if (closing) {
                    debug("Waiting for %s to close...", current_conversations.folder.to_string());
                    yield current_conversations.folder.wait_for_close_async(null);
                }
                
                debug("Stopped conversation monitor for %s", current_conversations.folder.to_string());
            }
        } catch (Error err) {
            message("Error closing conversation monitor %s at shutdown: %s",
                current_conversations.folder.to_string(), err.message);
        } finally {
            current_conversations = null;
        }
        
        // close all Inboxes
        foreach (Geary.Folder inbox in inboxes.values) {
            try {
                debug("Closing %s...", inbox.to_string());
                
                // close and wait for all pending operations to be flushed
                yield inbox.close_async(null);
                
                debug("Waiting for %s to close completely...", inbox.to_string());
                
                yield inbox.wait_for_close_async(null);
                
                debug("Closed %s", inbox.to_string());
            } catch (Error err) {
                message("Error closing Inbox %s at shutdown: %s", inbox.to_string(), err.message);
            }
        }
        
        // close all Accounts
        foreach (Geary.Account account in email_stores.keys) {
            try {
                debug("Closing account %s", account.to_string());
                yield account.close_async(null);
                debug("Closed account %s", account.to_string());
            } catch (Error err) {
                message("Error closing account %s at shutdown: %s", account.to_string(), err.message);
            }
        }
        
        main_window.destroy();
        
        // Turn off the lights and lock the door behind you
        try {
            debug("Closing Engine...");
            yield Geary.Engine.instance.close_async(null);
            debug("Closed Engine");
        } catch (Error err) {
            message("Error closing Geary Engine instance: %s", err.message);
        }
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
        
        Gtk.ActionEntry archive_message = { ACTION_ARCHIVE_MESSAGE, ARCHIVE_MESSAGE_ICON_NAME,
            ARCHIVE_MESSAGE_LABEL, "A", null, on_archive_message };
        archive_message.tooltip = ARCHIVE_MESSAGE_TOOLTIP_SINGLE;
        entries += archive_message;
        
        // although this action changes according to the account's capabilities, set to Delete
        // until they're known so the "translatable" string doesn't first appear
        Gtk.ActionEntry trash_message = { ACTION_TRASH_MESSAGE, TRASH_MESSAGE_ICON_NAME,
            null, "Delete", null, on_trash_message };
        trash_message.tooltip = TRASH_MESSAGE_TOOLTIP_SINGLE;
        entries += trash_message;
        add_accelerator("BackSpace", ACTION_TRASH_MESSAGE);
        
        Gtk.ActionEntry delete_message = { ACTION_DELETE_MESSAGE, DELETE_MESSAGE_ICON_NAME,
            null, "<Shift>Delete", null, on_delete_message };
        delete_message.tooltip = DELETE_MESSAGE_TOOLTIP_SINGLE;
        entries += delete_message;
        add_accelerator("<Shift>BackSpace", ACTION_DELETE_MESSAGE);
        
        Gtk.ActionEntry empty_menu = { ACTION_EMPTY_MENU, "edit-clear-all-symbolic", null, null,
            null, null };
        empty_menu.label = _("Empty");
        empty_menu.tooltip = _("Empty Spam or Trash folders");
        entries += empty_menu;
        
        Gtk.ActionEntry empty_spam = { ACTION_EMPTY_SPAM, null, null, null, null, on_empty_spam };
        empty_spam.label = _("Empty _Spam…");
        entries += empty_spam;
        
        Gtk.ActionEntry empty_trash = { ACTION_EMPTY_TRASH, null, null, null, null, on_empty_trash };
        empty_trash.label = _("Empty _Trash…");
        entries += empty_trash;
        
        Gtk.ActionEntry undo = { ACTION_UNDO, "edit-undo-symbolic", null, "<Ctrl>Z", null, on_revoke };
        entries += undo;
        
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
    
    private void setup_actions() {
        const string[] important_actions = {
            ACTION_NEW_MESSAGE,
            ACTION_REPLY_TO_MESSAGE,
            ACTION_REPLY_ALL_MESSAGE,
            ACTION_FORWARD_MESSAGE,
            ACTION_ARCHIVE_MESSAGE,
            ACTION_TRASH_MESSAGE,
            ACTION_DELETE_MESSAGE,
        };
        const string[] exported_actions = {
            ACTION_ACCOUNTS,
            ACTION_PREFERENCES,
            ACTION_DONATE,
            ACTION_HELP,
            ACTION_ABOUT,
            ACTION_QUIT,
        };
        
        Gtk.ActionGroup action_group = GearyApplication.instance.actions;
        
        Gtk.ActionEntry[] action_entries = create_actions();
        action_group.add_actions(action_entries, this);
        foreach (Gtk.ActionEntry e in action_entries) {
            Gtk.Action action = action_group.get_action(e.name);
            assert(action != null);
            
            if (e.name in important_actions)
                action.is_important = true;
            GearyApplication.instance.action_adapters.add(new Geary.ActionAdapter(action));
        }
        
        Gtk.ToggleActionEntry[] toggle_action_entries = create_toggle_actions();
        action_group.add_toggle_actions(toggle_action_entries, this);
        
        foreach (Geary.ActionAdapter a in GearyApplication.instance.action_adapters) {
            if (a.action.name in exported_actions)
                GearyApplication.instance.add_action(a.action);
        }
        GearyApplication.instance.ui_manager.insert_action_group(action_group, 0);
        
        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_file(
                GearyApplication.instance.get_ui_file("app_menu.interface").get_path());
        } catch (Error e) {
            error("Unable to parse app_menu.interface: %s", e.message);
        }
        MenuModel menu = (MenuModel) builder.get_object("app-menu");
        
        // We'd *like* to always export an app menu and just let the shell
        // decide whether to display it or not.  Unfortunately Mint (Cinnamon,
        // I believe) and maybe others will insert a menu bar for your
        // application, even if you didn't have one otherwise, if you export
        // the app menu.  So, we only export it if the shell claims to show it.
        if (Gtk.Settings.get_default().gtk_shell_shows_app_menu)
            GearyApplication.instance.set_app_menu(menu);
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
    
    private void on_untrusted_host(Geary.AccountInformation account_information,
        Geary.Endpoint endpoint, Geary.Endpoint.SecurityType security, TlsConnection cx,
        Geary.Service service) {
        prompt_untrusted_host_async.begin(account_information, endpoint, security, cx, service);
    }
    
    private async void prompt_untrusted_host_async(Geary.AccountInformation account_information,
        Geary.Endpoint endpoint, Geary.Endpoint.SecurityType security, TlsConnection cx,
        Geary.Service service) {
        // use a mutex to prevent multiple dialogs popping up at the same time
        int token = Geary.Nonblocking.Mutex.INVALID_TOKEN;
        try {
            token = yield untrusted_host_prompt_mutex.claim_async();
        } catch (Error err) {
            message("Unable to lock mutex to prompt user about invalid certificate: %s", err.message);
            
            return;
        }
        
        yield locked_prompt_untrusted_host_async(account_information, endpoint, security, cx,
            service);
        
        try {
            untrusted_host_prompt_mutex.release(ref token);
        } catch (Error err) {
            message("Unable to release mutex after prompting user about invalid certificate: %s",
                err.message);
        }
    }
    
    private static void get_gcr_params(Geary.Endpoint endpoint, out Gcr.Certificate cert,
        out string peer) {
        cert = new Gcr.SimpleCertificate(endpoint.untrusted_certificate.certificate.data);
        peer = "%s:%u".printf(endpoint.remote_address.hostname, endpoint.remote_address.port);
    }
    
    private async void locked_prompt_untrusted_host_async(Geary.AccountInformation account_information,
        Geary.Endpoint endpoint, Geary.Endpoint.SecurityType security, TlsConnection cx,
        Geary.Service service) {
        // possible while waiting on mutex that this endpoint became trusted or untrusted
        if (endpoint.trust_untrusted_host != Geary.Trillian.UNKNOWN)
            return;
        
        // get GCR parameters
        Gcr.Certificate cert;
        string peer;
        get_gcr_params(endpoint, out cert, out peer);
        
        // Geary allows for user to auto-revoke all questionable server certificates without
        // digging around in a keyring/pk manager
        if (Args.revoke_certs) {
            debug("Auto-revoking certificate for %s...", peer);
            
            try {
                gcr_trust_remove_pinned_certificate(cert, GCR_PURPOSE_SERVER_AUTH, peer, null);
            } catch (Error err) {
                message("Unable to auto-revoke server certificate for %s: %s", peer, err.message);
                
                // drop through, not absolutely valid to do this (might also mean certificate
                // was never pinned)
            }
        }
        
        // if pinned, the user has already made an exception for this server and its certificate,
        // so go ahead w/o asking
        try {
            if (gcr_trust_is_certificate_pinned(cert, GCR_PURPOSE_SERVER_AUTH, peer, null)) {
                debug("Certificate for %s is pinned, accepting connection...", peer);
                
                endpoint.trust_untrusted_host = Geary.Trillian.TRUE;
                
                return;
            }
        } catch (Error err) {
            message("Unable to check if server certificate for %s is pinned, assuming not: %s",
                peer, err.message);
        }
        
        // if these are in validation, there are complex GTK and workflow issues from simply
        // presenting the prompt now, so caller who connected will need to do it on their own dime
        if (!validating_endpoints.contains(endpoint))
            prompt_for_untrusted_host(main_window, account_information, endpoint, service, false);
    }
    
    private void prompt_for_untrusted_host(Gtk.Window? parent, Geary.AccountInformation account_information,
        Geary.Endpoint endpoint, Geary.Service service, bool is_validation) {
        CertificateWarningDialog dialog = new CertificateWarningDialog(parent, account_information,
            service, endpoint.tls_validation_warnings, is_validation);
        switch (dialog.run()) {
            case CertificateWarningDialog.Result.TRUST:
                endpoint.trust_untrusted_host = Geary.Trillian.TRUE;
            break;
            
            case CertificateWarningDialog.Result.ALWAYS_TRUST:
                endpoint.trust_untrusted_host = Geary.Trillian.TRUE;
                
                // get GCR parameters for pinning
                Gcr.Certificate cert;
                string peer;
                get_gcr_params(endpoint, out cert, out peer);
                
                // pinning the certificate creates an exception for the next time a connection
                // is attempted
                debug("Pinning certificate for %s...", peer);
                try {
                    gcr_trust_add_pinned_certificate(cert, GCR_PURPOSE_SERVER_AUTH, peer, null);
                } catch (Error err) {
                    ErrorDialog error_dialog = new ErrorDialog(main_window,
                        _("Unable to store server trust exception"), err.message);
                    error_dialog.run();
                }
            break;
            
            default:
                endpoint.trust_untrusted_host = Geary.Trillian.FALSE;
                
                // close the account; can't go any further w/o offline mode
                try {
                    if (Geary.Engine.instance.get_accounts().has_key(account_information.email)) {
                        Geary.Account account = Geary.Engine.instance.get_account_instance(account_information);
                        close_account(account);
                    }
                } catch (Error err) {
                    message("Unable to close account due to user trust issues: %s", err.message);
                }
            break;
        }
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
    
    // Returns possibly modified validation results
    private Geary.Engine.ValidationResult validation_check_endpoint_for_tls_warnings(
        Geary.AccountInformation account_information, Geary.Service service,
        Geary.Engine.ValidationResult validation_result, out bool prompted, out bool retry_required) {
        prompted = false;
        retry_required = false;
        
        // use LoginDialog for parent only if available and visible
        Gtk.Window? parent;
        if (login_dialog != null && login_dialog.visible)
            parent = login_dialog;
        else
            parent = main_window;
        
        Geary.Endpoint endpoint = account_information.get_endpoint_for_service(service);
        
        // If Endpoint had unresolved TLS issues, prompt user about them
        if (endpoint.tls_validation_warnings != 0 && endpoint.trust_untrusted_host != Geary.Trillian.TRUE) {
            prompt_for_untrusted_host(parent, account_information, endpoint, service, true);
            prompted = true;
        }
        
        // If there are still TLS connection issues that caused the connection to fail (happens on the
        // first attempt), clear those errors and retry
        if (endpoint.tls_validation_warnings != 0 && endpoint.trust_untrusted_host == Geary.Trillian.TRUE) {
            Geary.Engine.ValidationResult flag = (service == Geary.Service.IMAP)
                ? Geary.Engine.ValidationResult.IMAP_CONNECTION_FAILED
                : Geary.Engine.ValidationResult.SMTP_CONNECTION_FAILED;
            
            if ((validation_result & flag) != 0) {
                validation_result &= ~flag;
                retry_required = true;
            }
        }
        
        return validation_result;
    }
    
    // Use after validating to see if TLS warnings were handled by the user and need to retry the
    // validation; this will also modify the validation results to better indicate issues to the user
    //
    // Returns possibly modified validation results
    public async Geary.Engine.ValidationResult validation_check_for_tls_warnings_async(
        Geary.AccountInformation account_information, Geary.Engine.ValidationResult validation_result,
        out bool retry_required) {
        retry_required = false;
        
        // Because TLS warnings need cycles to process, sleep and give 'em a chance to do their
        // thing ... note that the signal handler does *not* invoke the user prompt dialog when the
        // login dialog is in play, so this sleep does not need to worry about user input
        yield Geary.Scheduler.sleep_ms_async(100);
        
        // check each service for problems, prompting user each time for verification
        bool imap_prompted, imap_retry_required;
        validation_result = validation_check_endpoint_for_tls_warnings(account_information,
            Geary.Service.IMAP, validation_result, out imap_prompted, out imap_retry_required);
        
        bool smtp_prompted, smtp_retry_required;
        validation_result = validation_check_endpoint_for_tls_warnings(account_information,
            Geary.Service.SMTP, validation_result, out smtp_prompted, out smtp_retry_required);
        
        // if prompted for user acceptance of bad certificates and they agreed to both, try again
        if (imap_prompted && smtp_prompted
            && account_information.get_imap_endpoint().is_trusted_or_never_connected
            && account_information.get_smtp_endpoint().is_trusted_or_never_connected) {
            retry_required = true;
        } else if (validation_result == Geary.Engine.ValidationResult.OK) {
            retry_required = true;
        } else {
            // if prompt requires retry or otherwise detected it, retry
            retry_required = imap_retry_required && smtp_retry_required;
        }
        
        return validation_result;
    }
    
    // Returns null if we are done validating, or the revised account information if we should retry.
    private async Geary.AccountInformation? validate_or_retry_async(Geary.AccountInformation account_information,
        Cancellable? cancellable = null) {
        Geary.Engine.ValidationResult result = yield validate_async(account_information,
            Geary.Engine.ValidationOption.CHECK_CONNECTIONS, cancellable);
        if (result == Geary.Engine.ValidationResult.OK)
            return null;
        
        // check Endpoints for trust (TLS) issues
        bool retry_required;
        result = yield validation_check_for_tls_warnings_async(account_information, result,
            out retry_required);
        
        // return for retry if required; check can also change validation results, in which case
        // revalidate entirely to have them written out
        if (retry_required)
            return account_information;
        
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
        // add Endpoints to set of validating endpoints to prevent the prompt from appearing
        validating_endpoints.add(account_information.get_imap_endpoint());
        validating_endpoints.add(account_information.get_smtp_endpoint());
        
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK;
        try {
            result = yield Geary.Engine.instance.validate_account_information_async(account_information,
                options, cancellable);
        } catch (Error err) {
            debug("Error validating account: %s", err.message);
            GearyApplication.instance.exit(-1); // Fatal error
            
            return result;
        }
        
        validating_endpoints.remove(account_information.get_imap_endpoint());
        validating_endpoints.remove(account_information.get_smtp_endpoint());
        
        if (result == Geary.Engine.ValidationResult.OK) {
            Geary.AccountInformation real_account_information = account_information;
            if (account_information.is_copy()) {
                // We have a temporary copy of the account.  Find the "real" acct info object and
                // copy the new data into it.
                real_account_information = get_real_account_information(account_information);
                real_account_information.copy_from(account_information);
            }
            
            real_account_information.store_async.begin(cancellable);
            do_update_stored_passwords_async.begin(Geary.ServiceFlag.IMAP | Geary.ServiceFlag.SMTP,
                real_account_information);
            
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
        if (login_dialog == null) {
            // Create here so we know GTK is initialized.
            login_dialog = new LoginDialog();
        } else if (!login_dialog.get_visible()) {
            // If the dialog has been dismissed, exit here.
            GearyApplication.instance.exit();
            
            return null;
        }
        
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
        
        return new_info;
    }
    
    private async void do_update_stored_passwords_async(Geary.ServiceFlag services,
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
                handle_outbox_failure(StatusBar.Message.OUTBOX_SEND_FAILURE);
            break;
            
            case Geary.Account.Problem.SAVE_SENT_MAIL_FAILED:
                handle_outbox_failure(StatusBar.Message.OUTBOX_SAVE_SENT_MAIL_FAILED);
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    private void handle_outbox_failure(StatusBar.Message message) {
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
            if (!main_window.status_bar.is_message_active(message))
                main_window.status_bar.activate_message(message);
            switch (message) {
                case StatusBar.Message.OUTBOX_SEND_FAILURE:
                    libnotify.set_error_notification(_("Error sending email"),
                        _("Geary encountered an error sending an email.  If the problem persists, please manually delete the email from your Outbox folder."));
                break;
                
                case StatusBar.Message.OUTBOX_SAVE_SENT_MAIL_FAILED:
                    libnotify.set_error_notification(_("Error saving sent mail"),
                        _("Geary encountered an error saving a sent message to Sent Mail.  The message will stay in your Outbox folder until you delete it."));
                break;
                
                default:
                    assert_not_reached();
            }
        }
    }
    
    private void on_account_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        if (folder.special_folder_type == Geary.SpecialFolderType.OUTBOX) {
            main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SEND_FAILURE);
            main_window.status_bar.deactivate_message(StatusBar.Message.OUTBOX_SAVE_SENT_MAIL_FAILED);
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
            !cancellable_open_account.is_cancelled() && !Args.hidden_startup)
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
        main_window.main_toolbar.update_trash_archive_buttons(
            current_folder_supports_trash() || !(current_folder is Geary.FolderSupport.Remove),
            current_account.can_support_archive);
    }
    
    private void on_folder_selected(Geary.Folder? folder) {
        debug("Folder %s selected", folder != null ? folder.to_string() : "(null)");
        
        // If the folder is being unset, clear the message list and exit here.
        if (folder == null) {
            current_folder = null;
            main_window.conversation_list_store.clear();
            main_window.main_toolbar.subtitle = null;
            folder_selected(null);
            
            return;
        }
        
        folder_to_select = folder;
        
        // To prevent the user from selecting folders too quickly, we prevent additional selection
        // changes to occur until after a timeout has expired from the last one
        int64 now = get_monotonic_time();
        int64 diff = now - next_folder_select_allowed_usec;
        if (diff < SELECT_FOLDER_TIMEOUT_USEC) {
            // only start timeout if another timeout is not running ... this means the user can
            // click madly and will see the last clicked-on folder 100ms after the first one was
            // clicked on
            if (select_folder_timeout_id == 0)
                select_folder_timeout_id = Timeout.add((uint) (diff / 1000), on_select_folder_timeout);
        } else {
            do_select_folder.begin(folder_to_select, on_select_folder_completed);
            folder_to_select = null;
            
            next_folder_select_allowed_usec = now + SELECT_FOLDER_TIMEOUT_USEC;
        }
    }
    
    private bool on_select_folder_timeout() {
        select_folder_timeout_id = 0;
        next_folder_select_allowed_usec = 0;
        
        if (folder_to_select != null)
            do_select_folder.begin(folder_to_select, on_select_folder_completed);
        
        folder_to_select = null;
        
        return false;
    }
    
    private async void do_select_folder(Geary.Folder folder) throws Error {
        if (folder == current_folder)
            return;
        
        debug("Switching to %s...", folder.to_string());
        
        closed_folder();
        
        // This function is not reentrant.  It should be, because it can be
        // called reentrant-ly if you select folders quickly enough.  This
        // mutex lock is a bandaid solution to make the function safe to
        // reenter.
        int mutex_token = yield select_folder_mutex.claim_async(cancellable_folder);
        
        bool current_is_inbox = inboxes.values.contains(current_folder);
        
        Cancellable? conversation_cancellable = (current_is_inbox ?
            inbox_cancellables.get(folder.account) : cancellable_folder);
        
        // clear Revokable, as Undo is only available while a folder is selected
        save_revokable(null, null);
        
        // stop monitoring for conversations and close the folder
        if (current_conversations != null) {
            yield current_conversations.stop_monitoring_async(null);
            current_conversations = null;
        }
        
        // re-enable copy/move to the last selected folder
        if (current_folder != null) {
            main_window.main_toolbar.copy_folder_menu.enable_disable_folder(current_folder, true);
            main_window.main_toolbar.move_folder_menu.enable_disable_folder(current_folder, true);
        }
        
        current_folder = folder;
        
        if (current_account != folder.account) {
            current_account = folder.account;
            account_selected(current_account);
            
            // If we were waiting for an account to be selected before issuing mailtos, do that now.
            if (pending_mailtos.size > 0) {
                foreach(string mailto in pending_mailtos)
                    compose_mailto(mailto);
                
                pending_mailtos.clear();
            }
        }
        
        folder_selected(current_folder);
        
        if (!(current_folder is Geary.SearchFolder))
            previous_non_search_folder = current_folder;
        
        main_window.main_toolbar.copy_folder_menu.clear();
        main_window.main_toolbar.move_folder_menu.clear();
        foreach(Geary.Folder f in current_folder.account.list_folders()) {
            main_window.main_toolbar.copy_folder_menu.add_folder(f);
            main_window.main_toolbar.move_folder_menu.add_folder(f);
        }
        
        // disable copy/move to the new folder
        if (current_folder != null) {
            main_window.main_toolbar.copy_folder_menu.enable_disable_folder(current_folder, false);
            main_window.main_toolbar.move_folder_menu.enable_disable_folder(current_folder, false);
        }
        
        update_ui();
        
        current_conversations = new Geary.App.ConversationMonitor(current_folder, Geary.Folder.OpenFlags.NO_DELAY,
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
        
        debug("Switched to %s", folder.to_string());
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
        
        if (folder == null || email == null || !can_switch_conversation_view())
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
        on_edit_draft(activated.get_latest_recv_email(Geary.App.Conversation.Location.IN_FOLDER));
    }
    
    private void on_edit_draft(Geary.Email draft) {
        create_compose_widget(ComposerWidget.ComposeType.NEW_MESSAGE, draft, null, null, true);
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
                main_window.folder_list.remove_folder(folder);
                if (folder.account == current_account) {
                    if (main_window.main_toolbar.copy_folder_menu.has_folder(folder))
                        main_window.main_toolbar.copy_folder_menu.remove_folder(folder);
                    if (main_window.main_toolbar.move_folder_menu.has_folder(folder))
                        main_window.main_toolbar.move_folder_menu.remove_folder(folder);
                }
                
                if (folder.special_folder_type == Geary.SpecialFolderType.INBOX &&
                    inboxes.has_key(folder.account)) {
                    inboxes.unset(folder.account);
                    new_messages_monitor.remove_folder(folder);
                }
                
                folder.special_folder_type_changed.disconnect(on_special_folder_type_changed);
            }
        }
    }
    
    private void cancel_folder() {
        Cancellable old_cancellable = cancellable_folder;
        cancellable_folder = new Cancellable();
        
        old_cancellable.cancel();
    }
    
    // Like cancel_folder() but doesn't cancel outstanding operations, allowing them to complete
    // in the background
    private void closed_folder() {
        cancellable_folder = new Cancellable();
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
    // GearyApplication.exiting's signature.
    private bool on_application_exiting(GearyApplication sender, bool panicked) {
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
            "license-type", Gtk.License.LGPL_2_1,
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
    
    private void on_shift_key(bool pressed) {
        if (main_window != null && main_window.main_toolbar != null
            && current_account != null && current_folder != null) {
            main_window.main_toolbar.update_trash_archive_buttons(
                (!pressed && current_folder_supports_trash()) || !(current_folder is Geary.FolderSupport.Remove),
                current_account.can_support_archive);
        }
    }
    
    // this signal does not necessarily indicate that the application previously didn't have
    // focus and now it does
    private void on_has_toplevel_focus() {
        clear_new_messages("on_has_toplevel_focus", null);
    }
    
    private void on_accounts() {
        AccountDialog dialog = new AccountDialog(main_window);
        dialog.show_all();
        dialog.run();
        dialog.destroy();
    }
    
    private void on_preferences() {
        PreferencesDialog dialog = new PreferencesDialog(main_window);
        dialog.run();
    }
    
    // latest_sent_only uses Email's Date: field, which corresponds to how they're sorted in the
    // ConversationViewer
    private Gee.ArrayList<Geary.EmailIdentifier> get_conversation_email_ids(
        Geary.App.Conversation conversation, bool latest_sent_only,
        Gee.ArrayList<Geary.EmailIdentifier> add_to) {
        if (latest_sent_only) {
            Geary.Email? latest = conversation.get_latest_sent_email(
                Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
            if (latest != null)
                add_to.add(latest.id);
        } else {
            add_to.add_all(conversation.get_email_ids());
        }
        
        return add_to;
    }
    
    private Gee.Collection<Geary.EmailIdentifier> get_conversation_collection_email_ids(
        Gee.Collection<Geary.App.Conversation> conversations, bool latest_sent_only) {
        Gee.ArrayList<Geary.EmailIdentifier> ret = new Gee.ArrayList<Geary.EmailIdentifier>();
        
        foreach(Geary.App.Conversation c in conversations)
            get_conversation_email_ids(c, latest_sent_only, ret);
        
        return ret;
    }
    
    private Gee.ArrayList<Geary.EmailIdentifier> get_selected_email_ids(bool latest_sent_only) {
        Gee.ArrayList<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.App.Conversation conversation in selected_conversations)
            get_conversation_email_ids(conversation, latest_sent_only, ids);
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
            
            // Only check the messages that "Mark as Unread" would mark, so we
            // don't add the menu option and have it not do anything.
            //
            // Sort by Date: field to correspond with ConversationViewer ordering
            Geary.Email? latest = conversation.get_latest_sent_email(
                Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
            if (latest != null && latest.email_flags != null
                && !latest.email_flags.contains(Geary.EmailFlags.UNREAD))
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
        
        if (current_folder.special_folder_type != Geary.SpecialFolderType.DRAFTS &&
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
            // We're in Drafts/Outbox, so gray-out the option.
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
        bool latest_only = false) {
        mark_email(get_conversation_collection_email_ids(conversations, latest_only),
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
        
        Gee.ArrayList<Geary.EmailIdentifier> ids = get_selected_email_ids(true);
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
    
    private async void mark_as_spam_async(Cancellable? cancellable) {
        Geary.Folder? destination_folder = null;
        if (current_folder.special_folder_type != Geary.SpecialFolderType.SPAM) {
            // Move to spam folder.
            try {
                destination_folder = yield current_account.get_required_special_folder_async(
                    Geary.SpecialFolderType.SPAM, cancellable);
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
    
    private void on_mark_as_spam() {
        mark_as_spam_async.begin(null);
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
        if (supports_move != null)
            move_conversation_async.begin(supports_move, ids, destination.path, cancellable_folder);
    }
    
    private async void move_conversation_async(Geary.FolderSupport.Move source_folder,
        Gee.List<Geary.EmailIdentifier> ids, Geary.FolderPath destination, Cancellable? cancellable) {
        try {
            save_revokable(yield source_folder.move_email_async(ids, destination, cancellable),
                _("Undo move (Ctrl+Z)"));
        } catch (Error err) {
            debug("%s: Unable to move %d emails: %s", source_folder.to_string(), ids.size,
                err.message);
        }
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
        
        // Open the attachment if we know what to do with it.
        if (!open_uri(attachment.file.get_uri())) {
            // Failing that, trigger a save dialog.
            Gee.List<Geary.Attachment> attachment_list = new Gee.ArrayList<Geary.Attachment>();
            attachment_list.add(attachment);
            on_save_attachments(attachment_list);
        }
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
        string? filename = dialog.get_filename();
        
        dialog.destroy();
        
        if (!accepted || Geary.String.is_empty(filename))
            return;
        
        File destination = File.new_for_path(filename);
        
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
    private bool open_uri(string _link) {
        string link = _link;
        
        // Support web URLs that ommit the protocol.
        if (!link.contains(":"))
            link = "http://" + link;
        
        bool ret = false;
        try {
            ret = Gtk.show_uri(main_window.get_screen(), link, Gdk.CURRENT_TIME);
        } catch (Error err) {
            debug("Unable to open URL. %s", err.message);
        }
        
        return ret;
    }
    
    private bool close_composition_windows() {
        Gee.List<ComposerWidget> composers_to_destroy = new Gee.ArrayList<ComposerWidget>();
        bool quit_cancelled = false;
        
        // If there's composer windows open, give the user a chance to save or cancel.
        foreach(ComposerWidget cw in composer_widgets) {
            // Check if we should close the window immediately, or if we need to wait.
            ComposerWidget.CloseStatus status = cw.should_close();
            if (status == ComposerWidget.CloseStatus.PENDING_CLOSE) {
                // Window is currently busy saving.
                waiting_to_close.add(cw);
            } else if (status == ComposerWidget.CloseStatus.CANCEL_CLOSE) {
                // User cancelled operation.
                quit_cancelled = true;
                break;
            } else if (status == ComposerWidget.CloseStatus.DO_CLOSE) {
                // Hide any existing composer windows for the moment; actually deleting the windows
                // will result in their removal from composer_windows, which could crash this loop.
                composers_to_destroy.add(cw);
                ((ComposerContainer) cw.parent).vanish();
            }
        }
        
        // Safely destroy windows.
        foreach(ComposerWidget cw in composers_to_destroy)
            ((ComposerContainer) cw.parent).close_container();
        
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
    
    // message is the email from whose menu this reply or forward was triggered.  If null,
    // this was triggered from the headerbar or shortcut.
    private void create_reply_forward_widget(ComposerWidget.ComposeType compose_type,
        Geary.Email? message) {
        string? quote;
        Geary.Email? quote_message = main_window.conversation_viewer.get_selected_message(out quote);
        if (message == null)
            message = quote_message;
        if (quote_message != message)
            quote = null;
        create_compose_widget(compose_type, message, quote);
    }
    
    private void create_compose_widget(ComposerWidget.ComposeType compose_type,
        Geary.Email? referred = null, string? quote = null, string? mailto = null,
        bool is_draft = false) {
        create_compose_widget_async.begin(compose_type, referred, quote, mailto, is_draft);
    }
    
    private async void create_compose_widget_async(ComposerWidget.ComposeType compose_type,
        Geary.Email? referred = null, string? quote = null, string? mailto = null,
        bool is_draft = false) {
        if (current_account == null)
            return;
        
        bool inline;
        if (!should_create_new_composer(compose_type, referred, quote, is_draft, out inline))
            return;
        
        ComposerWidget widget;
        if (mailto != null) {
            widget = new ComposerWidget.from_mailto(current_account, mailto);
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
            
            widget = new ComposerWidget(current_account, compose_type, full, quote, is_draft);
            if (is_draft) {
                yield widget.restore_draft_state_async(current_account);
                main_window.conversation_viewer.blacklist_by_id(referred.id);
            }
        }
        widget.show_all();
        
        // We want to keep track of the open composer windows, so we can allow the user to cancel
        // an exit without losing their data.
        composer_widgets.add(widget);
        debug(@"Creating composer of type $(widget.compose_type); $(composer_widgets.size) composers total");
        widget.destroy.connect(on_composer_widget_destroy);
        
        if (inline) {
            if (widget.state == ComposerWidget.ComposerState.NEW ||
                widget.state == ComposerWidget.ComposerState.PANED)
                main_window.conversation_viewer.set_paned_composer(widget);
            else
                new ComposerEmbed(widget, main_window.conversation_viewer, referred); // is_draft
        } else {
            new ComposerWindow(widget);
            widget.state = ComposerWidget.ComposerState.DETACHED;
        }
    }
    
    private bool should_create_new_composer(ComposerWidget.ComposeType? compose_type,
        Geary.Email? referred, string? quote, bool is_draft, out bool inline) {
        inline = true;
        
        // In we're replying, see whether we already have a reply for that message.
        if (compose_type != null && compose_type != ComposerWidget.ComposeType.NEW_MESSAGE) {
            foreach (ComposerWidget cw in composer_widgets) {
                if (cw.state != ComposerWidget.ComposerState.DETACHED &&
                    ((referred != null && cw.referred_ids.contains(referred.id)) ||
                     quote != null)) {
                    cw.change_compose_type(compose_type, referred, quote);
                    return false;
                }
            }
            inline = !any_inline_composers();
            return true;
        }
        
        // If there are no inline composers, go ahead!
        if (!any_inline_composers())
            return true;
        
        // If we're resuming a draft with open composers, open in a new window.
        if (is_draft) {
            inline = false;
            return true;
        }
        
        // If we're creating a new message, and there's already a new message open, focus on
        // it if it hasn't been modified; otherwise open a new composer in a new window.
        if (compose_type == ComposerWidget.ComposeType.NEW_MESSAGE) {
            foreach (ComposerWidget cw in composer_widgets) {
                if (cw.state == ComposerWidget.ComposerState.NEW) {
                    if (!cw.blank) {
                        inline = false;
                        return true;
                    } else {
                        cw.change_compose_type(compose_type);  // To refocus
                        return false;
                    }
                }
            }
        }
        
        // Find out what to do with the inline composers.
        // TODO: Remove this in favor of automatically saving drafts
        main_window.present();
        QuestionDialog dialog = new QuestionDialog(main_window, _("Close open draft messages?"), null,
            Stock._CLOSE, Stock._CANCEL);
        if (dialog.run() == Gtk.ResponseType.OK) {
            Gee.List<ComposerWidget> composers_to_destroy = new Gee.ArrayList<ComposerWidget>();
            foreach (ComposerWidget cw in composer_widgets) {
                if (cw.state != ComposerWidget.ComposerState.DETACHED)
                    composers_to_destroy.add(cw);
            }
            foreach(ComposerWidget cw in composers_to_destroy)
                ((ComposerContainer) cw.parent).close_container();
            return true;
        }
        return false;
    }
    
    public bool can_switch_conversation_view() {
        bool inline;
        return should_create_new_composer(null, null, null, false, out inline);
    }
    
    public bool any_inline_composers() {
        foreach (ComposerWidget cw in composer_widgets)
            if (cw.state != ComposerWidget.ComposerState.DETACHED)
                return true;
        return false;
    }
    
    private void on_composer_widget_destroy(Gtk.Widget sender) {
        composer_widgets.remove((ComposerWidget) sender);
        debug(@"Destroying composer of type $(((ComposerWidget) sender).compose_type); "
            + @"$(composer_widgets.size) composers remaining");
        
        if (waiting_to_close.remove((ComposerWidget) sender)) {
            // If we just removed the last window in the waiting to close list, it's time to exit!
            if (waiting_to_close.size == 0)
                GearyApplication.instance.exit();
        }
    }
    
    private void on_new_message() {
        create_compose_widget(ComposerWidget.ComposeType.NEW_MESSAGE);
    }
    
    private void on_reply_to_message(Geary.Email message) {
        create_reply_forward_widget(ComposerWidget.ComposeType.REPLY, message);
    }
    
    private void on_reply_to_message_action() {
        create_reply_forward_widget(ComposerWidget.ComposeType.REPLY, null);
    }
    
    private void on_reply_all_message(Geary.Email message) {
        create_reply_forward_widget(ComposerWidget.ComposeType.REPLY_ALL, message);
    }
    
    private void on_reply_all_message_action() {
        create_reply_forward_widget(ComposerWidget.ComposeType.REPLY_ALL, null);
    }
    
    private void on_forward_message(Geary.Email message) {
        create_reply_forward_widget(ComposerWidget.ComposeType.FORWARD, message);
    }
    
    private void on_forward_message_action() {
        create_reply_forward_widget(ComposerWidget.ComposeType.FORWARD, null);
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
    
    private void on_archive_message() {
        archive_or_delete_selection_async.begin(true, false, cancellable_folder,
            on_archive_or_delete_selection_finished);
    }
    
    private void on_trash_message() {
        archive_or_delete_selection_async.begin(false, true, cancellable_folder,
            on_archive_or_delete_selection_finished);
    }
    
    private void on_delete_message() {
        archive_or_delete_selection_async.begin(false, false, cancellable_folder,
            on_archive_or_delete_selection_finished);
    }
    
    private void on_empty_spam() {
        on_empty_trash_or_spam(Geary.SpecialFolderType.SPAM);
    }
    
    private void on_empty_trash() {
        on_empty_trash_or_spam(Geary.SpecialFolderType.TRASH);
    }
    
    private void on_empty_trash_or_spam(Geary.SpecialFolderType special_folder_type) {
        // Account must be in place, must have the specified special folder type, and that folder
        // must support Empty in order for this command to proceed
        if (current_account == null)
            return;
        
        Geary.Folder? folder = null;
        try {
            folder = current_account.get_special_folder(special_folder_type);
        } catch (Error err) {
            debug("%s: Unable to get special folder %s: %s", current_account.to_string(),
                special_folder_type.to_string(), err.message);
            
            // fall through
        }
        
        if (folder == null)
            return;
        
        Geary.FolderSupport.Empty? emptyable = folder as Geary.FolderSupport.Empty;
        if (emptyable == null) {
            debug("%s: Special folder %s (%s) does not support emptying", current_account.to_string(),
                folder.path.to_string(), special_folder_type.to_string());
            
            return;
        }
        
        ConfirmationDialog dialog = new ConfirmationDialog(main_window,
            _("Empty all email from your %s folder?").printf(special_folder_type.get_display_name()),
            _("This removes the email from Geary and your email server.")
                + "  <b>" + _("This cannot be undone.") + "</b>",
            _("Empty %s").printf(special_folder_type.get_display_name()));
        dialog.use_secondary_markup(true);
        dialog.set_focus_response(Gtk.ResponseType.CANCEL);
        
        if (dialog.run() == Gtk.ResponseType.OK)
            empty_folder_async.begin(emptyable, cancellable_folder);
    }
    
    private async void empty_folder_async(Geary.FolderSupport.Empty emptyable, Cancellable? cancellable) {
        try {
            yield do_empty_folder_async(emptyable, cancellable);
        } catch (Error err) {
            // don't report to user if cancelled
            if (cancellable is IOError.CANCELLED)
                return;
            
            ErrorDialog dialog = new ErrorDialog(main_window,
                _("Error emptying %s").printf(emptyable.get_display_name()), err.message);
            dialog.run();
        }
    }
    
    private async void do_empty_folder_async(Geary.FolderSupport.Empty emptyable, Cancellable? cancellable)
        throws Error {
        yield emptyable.open_async(Geary.Folder.OpenFlags.NONE, cancellable);
        
        // be sure to close in all code paths
        try {
            yield emptyable.empty_folder_async(cancellable);
        } finally {
            try {
                yield emptyable.close_async(null);
            } catch (Error err) {
                // ignored
            }
        }
    }
    
    private bool current_folder_supports_trash() {
        return (current_folder != null && current_folder.special_folder_type != Geary.SpecialFolderType.TRASH
            && !current_folder.properties.is_local_only && current_account != null
            && (current_folder as Geary.FolderSupport.Move) != null);
    }
    
    public bool confirm_delete(int num_messages) {
        main_window.present();
        AlertDialog dialog = new ConfirmationDialog(main_window, ngettext(
            "Do you want to permanently delete this message?",
            "Do you want to permanently delete these messages?", num_messages),
            null, _("Delete"));
        
        return (dialog.run() == Gtk.ResponseType.OK);
    }
    
    private async void archive_or_delete_selection_async(bool archive, bool trash,
        Cancellable? cancellable) throws Error {
        if (!can_switch_conversation_view())
            return;
        
        if (main_window.conversation_viewer.current_conversation != null
            && main_window.conversation_viewer.current_conversation == last_deleted_conversation) {
            debug("Not archiving/trashing/deleting; viewed conversation is last deleted conversation");
            return;
        }
        
        last_deleted_conversation = selected_conversations.size > 0
            ? Geary.traverse<Geary.App.Conversation>(selected_conversations).first() : null;
        
        // Return focus to the conversation list from the clicked toolbar button.
        main_window.conversation_list_view.grab_focus();
        
        Gee.List<Geary.EmailIdentifier> ids = get_selected_email_ids(false);
        if (archive) {
            debug("Archiving selected messages");
            
            Geary.FolderSupport.Archive? supports_archive = current_folder as Geary.FolderSupport.Archive;
            if (supports_archive == null) {
                debug("Folder %s doesn't support archive", current_folder.to_string());
            } else {
                save_revokable(yield supports_archive.archive_email_async(ids, cancellable),
                    _("Undo archive (Ctrl+Z)"));
            }
            
            return;
        }
        
        if (trash) {
            debug("Trashing selected messages");
            
            if (current_folder_supports_trash()) {
                Geary.FolderPath trash_path = (yield current_account.get_required_special_folder_async(
                    Geary.SpecialFolderType.TRASH, cancellable)).path;
                Geary.FolderSupport.Move? supports_move = current_folder as Geary.FolderSupport.Move;
                if (supports_move != null) {
                    save_revokable(yield supports_move.move_email_async(ids, trash_path, cancellable),
                        _("Undo trash (Ctrl+Z)"));
                    
                    return;
                }
            }
            
            debug("Folder %s doesn't support move or account %s doesn't have a trash folder",
                current_folder.to_string(), current_account.to_string());
            return;
        }
        
        debug("Deleting selected messages");
        
        Geary.FolderSupport.Remove? supports_remove = current_folder as Geary.FolderSupport.Remove;
        if (supports_remove == null) {
            debug("Folder %s doesn't support remove", current_folder.to_string());
        } else {
            if (confirm_delete(ids.size))
                yield supports_remove.remove_email_async(ids, cancellable);
            else
                last_deleted_conversation = null;
        }
    }
    
    private void on_archive_or_delete_selection_finished(Object? source, AsyncResult result) {
        try {
            archive_or_delete_selection_async.end(result);
        } catch (Error e) {
            debug("Unable to archive/trash/delete messages: %s", e.message);
        }
    }
    
    private void save_revokable(Geary.Revokable? new_revokable, string? description) {
        // disconnect old revokable & blindly commit it
        if (revokable != null) {
            revokable.notify[Geary.Revokable.PROP_VALID].disconnect(on_revokable_valid_changed);
            revokable.notify[Geary.Revokable.PROP_IN_PROCESS].disconnect(update_revokable_action);
            revokable.committed.disconnect(on_revokable_committed);
            
            revokable.commit_async.begin();
        }
        
        // store new revokable
        revokable = new_revokable;
        
        // connect to new revokable
        if (revokable != null) {
            revokable.notify[Geary.Revokable.PROP_VALID].connect(on_revokable_valid_changed);
            revokable.notify[Geary.Revokable.PROP_IN_PROCESS].connect(update_revokable_action);
            revokable.committed.connect(on_revokable_committed);
        }
        
        Gtk.Action undo_action = GearyApplication.instance.get_action(ACTION_UNDO);
        undo_action.tooltip = (revokable != null && description != null) ? description : _("Undo (Ctrl+Z)");
        
        update_revokable_action();
    }
    
    private void update_revokable_action() {
        Gtk.Action undo_action = GearyApplication.instance.get_action(ACTION_UNDO);
        undo_action.sensitive = revokable != null && revokable.valid && !revokable.in_process;
    }
    
    private void on_revokable_valid_changed() {
        // remove revokable if it goes invalid
        if (revokable != null && !revokable.valid)
            save_revokable(null, null);
    }
    
    private void on_revokable_committed(Geary.Revokable? committed_revokable) {
        if (committed_revokable == null)
            return;
        
        // use existing description
        Gtk.Action undo_action = GearyApplication.instance.get_action(ACTION_UNDO);
        save_revokable(committed_revokable, undo_action.tooltip);
    }
    
    private void on_revoke() {
        if (revokable != null && revokable.valid)
            revokable.revoke_async.begin(null, on_revoke_completed);
    }
    
    private void on_revoke_completed(Object? object, AsyncResult result) {
        // Don't use the "revokable" instance because it might have gone null before this callback
        // was reached
        Geary.Revokable? origin = object as Geary.Revokable;
        if (origin == null)
            return;
        
        try {
            origin.revoke_async.end(result);
        } catch (Error err) {
            debug("Unable to revoke operation: %s", err.message);
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
        GearyApplication.instance.actions.get_action(ACTION_ARCHIVE_MESSAGE).sensitive =
            (current_folder is Geary.FolderSupport.Archive);
        GearyApplication.instance.actions.get_action(ACTION_TRASH_MESSAGE).sensitive =
            current_folder_supports_trash();
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive =
            (current_folder is Geary.FolderSupport.Remove);
        
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
        GearyApplication.instance.actions.get_action(ACTION_ARCHIVE_MESSAGE).sensitive = sensitive
            && (current_folder is Geary.FolderSupport.Archive);
        GearyApplication.instance.actions.get_action(ACTION_TRASH_MESSAGE).sensitive = sensitive
            && current_folder_supports_trash();
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).sensitive = sensitive
            && (current_folder is Geary.FolderSupport.Remove);
        
        cancel_context_dependent_buttons();
        enable_context_dependent_buttons_async.begin(sensitive, cancellable_context_dependent_buttons);
    }
    
    private async void enable_context_dependent_buttons_async(bool sensitive, Cancellable? cancellable) {
        Gee.MultiMap<Geary.EmailIdentifier, Type>? selected_operations = null;
        try {
            if (current_folder != null) {
                Geary.App.EmailStore? store = email_stores.get(current_folder.account);
                if (store != null) {
                    selected_operations = yield store
                        .get_supported_operations_async(get_selected_email_ids(false), cancellable);
                }
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
        
        GearyApplication.instance.actions.get_action(ACTION_ARCHIVE_MESSAGE).tooltip = single ?
            ARCHIVE_MESSAGE_TOOLTIP_SINGLE : ARCHIVE_MESSAGE_TOOLTIP_MULTIPLE;
        GearyApplication.instance.actions.get_action(ACTION_TRASH_MESSAGE).tooltip = single ?
            TRASH_MESSAGE_TOOLTIP_SINGLE : TRASH_MESSAGE_TOOLTIP_MULTIPLE;
        GearyApplication.instance.actions.get_action(ACTION_DELETE_MESSAGE).tooltip = single ?
            DELETE_MESSAGE_TOOLTIP_SINGLE : DELETE_MESSAGE_TOOLTIP_MULTIPLE;
    }
    
    public void compose_mailto(string mailto) {
        if (current_account == null) {
            // Schedule the send for after we have an account open.
            pending_mailtos.add(mailto);
            
            return;
        }
        
        create_compose_widget(ComposerWidget.ComposeType.NEW_MESSAGE, null, null, mailto);
    }
    
    // Returns a list of composer windows for an account, or null if none.
    public Gee.List<ComposerWidget>? get_composer_widgets_for_account(Geary.AccountInformation account) {
        Gee.LinkedList<ComposerWidget> ret = Geary.traverse<ComposerWidget>(composer_widgets)
            .filter(w => w.account.information == account)
            .to_linked_list();
        
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
        
        folder.search(search_text, GearyApplication.instance.config.get_search_strategy(),
            cancellable_search);
        
        main_window.folder_list.set_search(folder);
        search_text_changed(main_window.main_toolbar.search_text);
    }
    
    private void on_search_text_changed(string search_text) {
        // So we don't thrash the disk as the user types, we run the actual
        // search after a quick delay when they finish typing.
        if (search_timeout_id != 0)
            Source.remove(search_timeout_id);
        
        search_timeout_id = Timeout.add(SEARCH_TIMEOUT_MSEC, on_search_timeout, Priority.LOW);
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

