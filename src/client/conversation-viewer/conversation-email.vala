/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016,2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an email in a conversation.
 *
 * This view corresponds to {@link Geary.Email}, displaying the
 * email's primary message (a {@link Geary.RFC822.Message}), any
 * sub-messages (also instances of {@link Geary.RFC822.Message}) and
 * attachments. The RFC822 messages are themselves displayed by {@link
 * ConversationMessage}.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-email.ui")]
public class ConversationEmail : Gtk.Box, Geary.BaseInterface {
    // This isn't a Gtk.Grid since when added to a Gtk.ListBoxRow the
    // hover style isn't applied to it.

    private const string MANUAL_READ_CLASS = "geary-manual-read";
    private const string SENT_CLASS = "geary-sent";
    private const string STARRED_CLASS = "geary-starred";
    private const string UNREAD_CLASS = "geary-unread";

    /** Fields that must be available for constructing the view. */
    internal const Geary.Email.Field REQUIRED_FOR_CONSTRUCT = (
        Geary.Email.Field.ENVELOPE |
        Geary.Email.Field.PREVIEW |
        Geary.Email.Field.FLAGS
    );

    /** Fields that must be available for loading the body. */
    internal const Geary.Email.Field REQUIRED_FOR_LOAD = (
        // Include those needed by the constructor since we'll replace
        // the ctor's email arg value once the body has been fully
        // loaded
        REQUIRED_FOR_CONSTRUCT |
        Geary.Email.REQUIRED_FOR_MESSAGE
    );

    // Time to wait loading the body before showing the progress meter
    private const int BODY_LOAD_TIMEOUT_MSEC = 250;


    /** Specifies the loading state for a message part. */
    public enum LoadState {

        /** Loading has not started. */
        NOT_STARTED,

        /** Loading has started, but not completed. */
        STARTED,

        /** Loading has started and completed. */
        COMPLETED,

        /** Loading has started but encountered an error. */
        FAILED;

    }

    /**
     * Iterator that returns all message views in an email view.
     */
    private class MessageViewIterator :
        Gee.Traversable<ConversationMessage>,
        Gee.Iterator<ConversationMessage>,
        Geary.BaseObject {


        public bool read_only {
            get { return true; }
        }
        public bool valid {
            get { return this.pos == 0 || this.attached_views.valid; }
        }

        private ConversationEmail parent_view;
        private int pos = -1;
        private Gee.Iterator<ConversationMessage>? attached_views = null;

        internal MessageViewIterator(ConversationEmail parent_view) {
            this.parent_view = parent_view;
            this.attached_views = parent_view._attached_messages.iterator();
        }

        public bool next() {
            bool has_next = false;
            this.pos += 1;
            if (this.pos == 0) {
                has_next = true;
            } else {
                has_next = this.attached_views.next();
            }
            return has_next;
        }

        public bool has_next() {
            return this.pos == -1 || this.attached_views.next();
        }

        public new ConversationMessage get() {
            switch (this.pos) {
            case -1:
                assert_not_reached();

            case 0:
                return this.parent_view.primary_message;

            default:
                return this.attached_views.get();
            }
        }

        public void remove() {
            assert_not_reached();
        }

        public new bool foreach(Gee.ForallFunc<ConversationMessage> f) {
            bool cont = true;
            while (cont && has_next()) {
                next();
                cont = f(get());
            }
            return cont;
        }

    }


    private static GLib.MenuModel email_menu_template;
    private static GLib.MenuModel email_menu_trash_section;
    private static GLib.MenuModel email_menu_delete_section;


    static construct {
        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-email-menus.ui"
        );
        email_menu_template = (GLib.MenuModel) builder.get_object("email_menu");
        email_menu_trash_section  = (GLib.MenuModel) builder.get_object("email_menu_trash");
        email_menu_delete_section = (GLib.MenuModel) builder.get_object("email_menu_delete");
    }


    /**
     * The specific email that is displayed by this view.
     *
     * This object is updated as additional fields are loaded, so it
     * should not be relied on to a) contain required fields without
     * testing or b) assumed to be the same over the life of this view
     * object.
     */
    public Geary.Email email { get; private set; }

    /** Determines if this email currently flagged as unread. */
    public bool is_unread {
        get {
            Geary.EmailFlags? flags = this.email.email_flags;
            return (flags != null && flags.is_unread());
        }
    }

    /** Determines if this email currently flagged as starred. */
    public bool is_starred {
        get {
            Geary.EmailFlags? flags = this.email.email_flags;
            return (flags != null && flags.is_flagged());
        }
    }

    /** Determines if the email is showing a preview or the full message. */
    public bool is_collapsed = true;

    /** Determines if the email has been manually marked as being read. */
    public bool is_manually_read {
        get { return get_style_context().has_class(MANUAL_READ_CLASS); }
        set {
            if (value) {
                get_style_context().add_class(MANUAL_READ_CLASS);
            } else {
                get_style_context().remove_class(MANUAL_READ_CLASS);
            }
        }
    }

    /** Determines if the email is a draft message. */
    public bool is_draft { get; private set; }

    /** The view displaying the email's primary message headers and body. */
    public ConversationMessage primary_message { get; private set; }

    public Components.AttachmentPane? attachments_pane {
        get; private set; default = null;
    }

    /** Views for attached messages. */
    public Gee.List<ConversationMessage> attached_messages {
        owned get { return this._attached_messages.read_only_view; }
    }
    private Gee.List<ConversationMessage> _attached_messages =
        new Gee.LinkedList<ConversationMessage>();

    /** Determines the message body loading state. */
    public LoadState message_body_state { get; private set; default = NOT_STARTED; }

    public Geary.App.Conversation conversation;

    // Store from which to load message content, if needed
    private Geary.App.EmailStore email_store;

    // Store from which to lookup contacts
    private Application.ContactStore contacts;

    // Cancellable to use when loading message content
    private GLib.Cancellable load_cancellable;

    private Application.Configuration config;

    private Geary.TimeoutManager body_loading_timeout;

    /** Determines if all message's web views have finished loading. */
    private Geary.Nonblocking.Spinlock message_bodies_loaded_lock;

    // Message view with selected text, if any
    private ConversationMessage? body_selection_message = null;

    // A subset of the message's attachments that are displayed in the
    // attachments view
    private Gee.List<Geary.Attachment> displayed_attachments =
         new Gee.LinkedList<Geary.Attachment>();

    // Tracks if Shift key handler has been installed on the main
    // window, for updating email menu trash/delete actions.
    private bool shift_handler_installed = false;

    [GtkChild] private unowned Gtk.Grid actions;

    [GtkChild] private unowned Gtk.Button attachments_button;

    [GtkChild] private unowned Gtk.Button star_button;

    [GtkChild] private unowned Gtk.Button unstar_button;

    [GtkChild] private unowned Gtk.MenuButton email_menubutton;

    [GtkChild] private unowned Gtk.Grid sub_messages;


    /** Fired when a internal link is activated */
    internal signal void internal_link_activated(int y);

    /** Fired when the user selects text in a message. */
    internal signal void body_selection_changed(bool has_selection);


    /**
     * Constructs a new view to display an email.
     *
     * This method sets up most of the user interface for displaying
     * the complete email, but does not attempt any possibly
     * long-running loading processes.
     */
    public ConversationEmail(Geary.App.Conversation conversation,
                             Geary.Email email,
                             Geary.App.EmailStore email_store,
                             Application.ContactStore contacts,
                             Application.Configuration config,
                             bool is_sent,
                             bool is_draft,
                             GLib.Cancellable load_cancellable) {
        base_ref();
        this.conversation = conversation;
        this.email = email;
        this.is_draft = is_draft;
        this.email_store = email_store;
        this.contacts = contacts;
        this.config = config;
        this.load_cancellable = load_cancellable;
        this.message_bodies_loaded_lock =
            new Geary.Nonblocking.Spinlock(load_cancellable);

        if (is_sent) {
            get_style_context().add_class(SENT_CLASS);
        }

        // Construct the view for the primary message, hook into it

        this.primary_message = new ConversationMessage.from_email(
            email,
            email.load_remote_images().is_certain(),
            this.contacts,
            this.config
        );
        this.primary_message.summary.add(this.actions);
        connect_message_view_signals(this.primary_message);

        // Wire up the rest of the UI

        email_store.account.incoming.notify["current-status"].connect(
            on_service_status_change
        );

        this.load_cancellable.cancelled.connect(on_load_cancelled);

        this.body_loading_timeout = new Geary.TimeoutManager.milliseconds(
            BODY_LOAD_TIMEOUT_MSEC, this.on_body_loading_timeout
        );

        pack_start(this.primary_message, true, true, 0);
        update_email_state();
    }

    ~ConversationEmail() {
        base_unref();
    }

    /**
     * Loads the contacts for the primary message.
     */
    public async void load_contacts()
        throws GLib.Error {
        try {
            yield this.primary_message.load_contacts(this.load_cancellable);
        } catch (IOError.CANCELLED err) {
            // okay
        } catch (Error err) {
            Geary.RFC822.MailboxAddress? from =
                this.primary_message.primary_originator;
            debug("Contact load failed for \"%s\": %s",
                  from != null ? from.to_string() : "<unknown>", err.message);
        }
        if (this.load_cancellable.is_cancelled()) {
            throw new GLib.IOError.CANCELLED("Contact load was cancelled");
        }
    }

    /**
     * Loads the message body and attachments.
     *
     * This potentially hits the database if the email that the view
     * was constructed from doesn't satisfy requirements, loads
     * attachments, including views and avatars for any attached
     * messages, and waits for the primary message body content to
     * have been loaded by its web view before returning.
     */
    public async void load_body()
        throws GLib.Error {
        this.message_body_state = STARTED;

        // Ensure we have required data to load the message

        bool loaded = this.email.fields.fulfills(REQUIRED_FOR_LOAD);
        if (!loaded) {
            this.body_loading_timeout.start();
            try {
                this.email = yield this.email_store.fetch_email_async(
                    this.email.id,
                    REQUIRED_FOR_LOAD,
                    LOCAL_ONLY, // Throws an error if not downloaded
                    this.load_cancellable
                );
                loaded = true;
                this.body_loading_timeout.reset();
            } catch (Geary.EngineError.INCOMPLETE_MESSAGE err) {
                // Don't have the complete message at the moment, so
                // download it in the background. Don't reset the body
                // load timeout here since this will attempt to fetch
                // from the remote
                this.fetch_remote_body.begin();
            } catch (GLib.IOError.CANCELLED err) {
                this.body_loading_timeout.reset();
                throw err;
            } catch (GLib.Error err) {
                this.body_loading_timeout.reset();
                handle_load_failure(err);
                throw err;
            }
        }

        if (loaded) {
            try {
                yield update_body();
            } catch (GLib.IOError.CANCELLED err) {
                this.body_loading_timeout.reset();
                throw err;
            } catch (GLib.Error err) {
                this.body_loading_timeout.reset();
                handle_load_failure(err);
                throw err;
            }
            yield this.message_bodies_loaded_lock.wait_async(
                this.load_cancellable
            );
        }
    }

    /**
     * Shows the complete message: headers, body and attachments.
     */
    public void expand_email(bool include_transitions=true) {
        this.is_collapsed = false;
        update_email_state();
        this.attachments_button.set_sensitive(true);
        // Needs at least some menu set otherwise it won't be enabled,
        // also has the side effect of making it sensitive
        this.email_menubutton.set_menu_model(new GLib.Menu());

        // Set targets to enable the actions
        GLib.Variant email_target = email.id.to_variant();
        this.attachments_button.set_action_target_value(email_target);
        this.star_button.set_action_target_value(email_target);
        this.unstar_button.set_action_target_value(email_target);

        foreach (ConversationMessage message in this) {
            message.show_message_body(include_transitions);
        }
    }

    /**
     * Hides the complete message, just showing the header preview.
     */
    public void collapse_email() {
        is_collapsed = true;
        update_email_state();
        attachments_button.set_sensitive(false);
        email_menubutton.set_sensitive(false);

        // Clear targets to disable the actions
        this.attachments_button.set_action_target_value(null);
        this.star_button.set_action_target_value(null);
        this.unstar_button.set_action_target_value(null);

        primary_message.hide_message_body();
        foreach (ConversationMessage attached in this._attached_messages) {
            attached.hide_message_body();
        }
    }

    /**
     * Updates the current email's flags and dependent UI state.
     */
    public void update_flags(Geary.Email email) {
        this.email.set_flags(email.email_flags);
        update_email_state();
    }

    /**
     * Returns user-selected body HTML from a message, if any.
     */
    public async string? get_selection_for_quoting() {
        string? selection = null;
        if (this.body_selection_message != null) {
            try {
                selection =
                   yield this.body_selection_message.get_selection_for_quoting();
            } catch (Error err) {
                debug("Failed to get selection for quoting: %s", err.message);
            }
        }
        return selection;
    }

    /**
     * Returns user-selected body text from a message, if any.
     */
    public async string? get_selection_for_find() {
        string? selection = null;
        if (this.body_selection_message != null) {
            try {
                selection =
                   yield this.body_selection_message.get_selection_for_find();
            } catch (Error err) {
                debug("Failed to get selection for find: %s", err.message);
            }
        }
        return selection;
    }

    /** Displays the raw RFC 822 source for this email. */
    public async void view_source() {
        var main = get_toplevel() as Application.MainWindow;
        if (main != null) {
            Geary.Email email = this.email;
            try {
                yield Geary.Nonblocking.Concurrent.global.schedule_async(
                    () => {
                        string source = (
                            email.header.buffer.to_string() +
                            email.body.buffer.to_string()
                        );
                        string temporary_filename;
                        int temporary_handle = GLib.FileUtils.open_tmp(
                            "geary-message-XXXXXX.txt",
                            out temporary_filename
                        );
                        GLib.FileUtils.set_contents(temporary_filename, source);
                        GLib.FileUtils.close(temporary_handle);

                        // ensure this file is only readable by the
                        // user ... this needs to be done after the
                        // file is closed
                        GLib.FileUtils.chmod(
                            temporary_filename,
                            (int) (Posix.S_IRUSR | Posix.S_IWUSR)
                        );

                        string temporary_uri = GLib.Filename.to_uri(
                            temporary_filename, null
                        );
                        main.application.show_uri.begin(temporary_uri);
                    },
                    null
                );
            } catch (GLib.Error error) {
                main.application.controller.report_problem(
                    new Geary.ProblemReport(error)
                );
            }
        }
    }

    /** Print this view's email. */
    public async void print() throws Error {
        Json.Builder builder = new Json.Builder();
        builder.begin_object();
        if (this.email.from != null) {
            builder.set_member_name(_("From:"));
            builder.add_string_value(this.email.from.to_string());
        }
        if (this.email.to != null) {
            // Translators: Human-readable version of the RFC 822 To header
            builder.set_member_name(_("To:"));
            builder.add_string_value(this.email.to.to_string());
        }
        if (this.email.cc != null) {
            // Translators: Human-readable version of the RFC 822 CC header
            builder.set_member_name(_("Cc:"));
            builder.add_string_value(this.email.cc.to_string());
        }
        if (this.email.bcc != null) {
            // Translators: Human-readable version of the RFC 822 BCC header
            builder.set_member_name(_("Bcc:"));
            builder.add_string_value(this.email.bcc.to_string());
        }
        if (this.email.date != null) {
            // Translators: Human-readable version of the RFC 822 Date header
            builder.set_member_name(_("Date:"));
            builder.add_string_value(
                Util.Date.pretty_print_verbose(
                    this.email.date.value.to_local(),
                    this.config.clock_format
                )
            );
        }
        if (this.email.subject != null) {
            // Translators: Human-readable version of the RFC 822 Subject header
            builder.set_member_name(_("Subject:"));
            builder.add_string_value(this.email.subject.to_string());
        }
        builder.end_object();
        Json.Generator generator = new Json.Generator();
        generator.set_root(builder.get_root());
        string js = "geary.addPrintHeaders(" + generator.to_data(null) + ");";
        yield this.primary_message.evaluate_javascript(js, null);

        Gtk.Window? window = get_toplevel() as Gtk.Window;
        WebKit.PrintOperation op = this.primary_message.new_print_operation();
        Gtk.PrintSettings settings = new Gtk.PrintSettings();

        // Use XDG_DOWNLOADS as default while WebKitGTK printing is
        // entirely b0rked on Flatpak, since we know at least have the
        // RW filesystem override in place to allow printing to PDF to
        // work, when using that directory.
        var download_dir = GLib.Environment.get_user_special_dir(DOWNLOAD);
        if (!Geary.String.is_empty_or_whitespace(download_dir)) {
            settings.set(Gtk.PRINT_SETTINGS_OUTPUT_DIR, download_dir);
        }

        if (this.email.subject != null) {
            string file_name = Geary.String.reduce_whitespace(this.email.subject.value);
            file_name = file_name.replace("/", "_");
            if (file_name.char_count() > 128) {
                file_name = Geary.String.safe_byte_substring(file_name, 128);
            }

            if (!Geary.String.is_empty(file_name)) {
                settings.set(Gtk.PRINT_SETTINGS_OUTPUT_BASENAME, file_name);
            }
        }

        op.set_print_settings(settings);
        op.run_dialog(window);
    }

    /**
     * Returns a new Iterable over all message views in this email view
     */
    internal Gee.Iterator<ConversationMessage> iterator() {
        return new MessageViewIterator(this);
    }

    private void connect_message_view_signals(ConversationMessage view) {
        view.content_loaded.connect(on_content_loaded);
        view.flag_remote_images.connect(on_flag_remote_images);
        view.internal_link_activated.connect((y) => {
                internal_link_activated(y);
            });
        view.internal_resource_loaded.connect(on_resource_loaded);
        view.save_image.connect(on_save_image);
        view.selection_changed.connect((has_selection) => {
                this.body_selection_message = has_selection ? view : null;
                body_selection_changed(has_selection);
            });
    }

    private async void fetch_remote_body() {
        if (is_online()) {
            // XXX Need proper progress reporting here, rather than just
            // doing a pulse
            if (!this.body_loading_timeout.is_running) {
                this.body_loading_timeout.start();
            }

            Geary.Email? loaded = null;
            try {
                debug("Downloading remote message: %s", this.email.to_string());
                loaded = yield this.email_store.fetch_email_async(
                    this.email.id,
                    REQUIRED_FOR_LOAD,
                    FORCE_UPDATE,
                    this.load_cancellable
                );
            } catch (GLib.IOError.CANCELLED err) {
                // All good
            } catch (GLib.Error err) {
                debug("Remote message download failed: %s", err.message);
                handle_load_failure(err);
            }

            this.body_loading_timeout.reset();

            if (loaded != null && !this.load_cancellable.is_cancelled()) {
                try {
                    this.email = loaded;
                    yield update_body();
                } catch (GLib.IOError.CANCELLED err) {
                    // All good
                } catch (GLib.Error err) {
                    debug("Remote message update failed: %s", err.message);
                    handle_load_failure(err);
                }
            }
        } else {
            this.body_loading_timeout.reset();
            handle_load_offline();
        }
    }

    private async void update_body()
        throws GLib.Error {
        Geary.RFC822.Message message = this.email.get_message();

        // Load all mime parts and construct CID resources from them

        Gee.Map<string,Geary.Memory.Buffer> cid_resources =
            new Gee.HashMap<string,Geary.Memory.Buffer>();
        foreach (Geary.Attachment attachment in email.attachments) {
            // Assume all parts are attachments. As the primary and
            // secondary message bodies are loaded, any displayed
            // inline will be removed from the list.
            this.displayed_attachments.add(attachment);

            if (attachment.content_id != null) {
                try {
                    cid_resources[attachment.content_id] =
                        new Geary.Memory.FileBuffer(attachment.file, true);
                } catch (Error err) {
                    debug("Could not open attachment: %s", err.message);
                }
            }
        }
        this.attachments_button.set_visible(!this.displayed_attachments.is_empty);

        // Load all messages

        this.primary_message.add_internal_resources(cid_resources);
        yield this.primary_message.load_message_body(
            message, this.load_cancellable
        );

        Gee.List<Geary.RFC822.Message> sub_messages = message.get_sub_messages();
        if (sub_messages.size > 0) {
            this.primary_message.body_container.add(this.sub_messages);
        }
        foreach (Geary.RFC822.Message sub_message in sub_messages) {
            ConversationMessage attached_message =
                new ConversationMessage.from_message(
                    sub_message,
                    this.email.load_remote_images().is_certain(),
                    this.contacts,
                    this.config
                );
            connect_message_view_signals(attached_message);
            attached_message.add_internal_resources(cid_resources);
            this.sub_messages.add(attached_message);
            this._attached_messages.add(attached_message);
            attached_message.load_contacts.begin(this.load_cancellable);
            yield attached_message.load_message_body(
                sub_message, this.load_cancellable
            );
            if (!this.is_collapsed) {
                attached_message.show_message_body(false);
            }
        }
    }

    private void update_email_state() {
        Gtk.StyleContext style = get_style_context();

        if (this.is_unread) {
            style.add_class(UNREAD_CLASS);
        } else {
            style.remove_class(UNREAD_CLASS);
        }

        if (this.is_starred) {
            style.add_class(STARRED_CLASS);
            this.star_button.hide();
            this.unstar_button.show();
        } else {
            style.remove_class(STARRED_CLASS);
            this.star_button.show();
            this.unstar_button.hide();
        }

        update_email_menu();
    }

    private void update_email_menu() {
        if (this.email_menubutton.active) {
            bool in_base_folder = this.conversation.is_in_base_folder(
                this.email.id
            );
            bool supports_trash = (
                in_base_folder &&
                Application.Controller.does_folder_support_trash(
                    this.conversation.base_folder
                )
            );
            bool supports_delete = (
                in_base_folder &&
                this.conversation.base_folder is Geary.FolderSupport.Remove
            );
            bool is_shift_down = false;
            var main = get_toplevel() as Application.MainWindow;
            if (main != null) {
                is_shift_down = main.is_shift_down;

                if (!this.shift_handler_installed) {
                    this.shift_handler_installed = true;
                    main.notify["is-shift-down"].connect(on_shift_changed);
                }
            }

            string[] blacklist = {};
            if (this.is_unread) {
                blacklist += (
                    ConversationListBox.EMAIL_ACTION_GROUP_NAME + "." +
                    ConversationListBox.ACTION_MARK_UNREAD
                );
                blacklist += (
                    ConversationListBox.EMAIL_ACTION_GROUP_NAME + "." +
                    ConversationListBox.ACTION_MARK_UNREAD_DOWN
                );
            } else {
                blacklist += (
                    ConversationListBox.EMAIL_ACTION_GROUP_NAME + "." +
                    ConversationListBox.ACTION_MARK_READ
                );
            }

            bool show_trash = !is_shift_down && supports_trash;
            bool show_delete = !show_trash && supports_delete;
            GLib.Variant email_target = email.id.to_variant();
            GLib.Menu new_model = Util.Gtk.construct_menu(
                email_menu_template,
                (menu, submenu, action, item) => {
                    bool accept = true;
                    if (submenu == email_menu_trash_section && !show_trash) {
                        accept = false;
                    }
                    if (submenu == email_menu_delete_section && !show_delete) {
                        accept = false;
                    }
                    if (action != null && !(action in blacklist)) {
                        item.set_action_and_target_value(
                            action, email_target
                        );
                    }
                    return accept;
                }
            );

            this.email_menubutton.popover.bind_model(new_model, null);
            this.email_menubutton.popover.grab_focus();
        }
    }


    private void update_displayed_attachments() {
        bool has_attachments = !this.displayed_attachments.is_empty;
        this.attachments_button.set_visible(has_attachments);
        var main = get_toplevel() as Application.MainWindow;

        if (has_attachments && main != null) {
            this.attachments_pane = new Components.AttachmentPane(
                false, main.attachments
            );
            this.primary_message.body_container.add(this.attachments_pane);

            foreach (var attachment in this.displayed_attachments) {
                this.attachments_pane.add_attachment(
                    attachment, this.load_cancellable
                );
            }
        }
    }

    private void handle_load_failure(GLib.Error error) {
        this.message_body_state = FAILED;
        this.primary_message.show_load_error_pane();

        var main = get_toplevel() as Application.MainWindow;
        if (main != null) {
            Geary.AccountInformation account = this.email_store.account.information;
            main.application.controller.report_problem(
                new Geary.ServiceProblemReport(account, account.incoming, error)
            );
        }
    }

    private void handle_load_offline() {
        this.message_body_state = FAILED;
        this.primary_message.show_offline_pane();
    }

    private inline bool is_online() {
        return (this.email_store.account.incoming.current_status == CONNECTED);
    }

    private void activate_email_action(string name) {
        GLib.ActionGroup? email_actions = get_action_group(
            ConversationListBox.EMAIL_ACTION_GROUP_NAME
        );
        if (email_actions != null) {
            email_actions.activate_action(name, this.email.id.to_variant());
        }
    }

    [GtkCallback]
    private void on_email_menu() {
        update_email_menu();
    }

    private void on_shift_changed() {
        update_email_menu();
    }

    private void on_body_loading_timeout() {
        this.primary_message.show_loading_pane();
    }

    private void on_load_cancelled() {
        this.body_loading_timeout.reset();
    }

    private void on_flag_remote_images() {
        activate_email_action(ConversationListBox.ACTION_MARK_LOAD_REMOTE);
    }

    private void on_save_image(string uri,
                               string? alt_text,
                               Geary.Memory.Buffer? content) {
        var main = get_toplevel() as Application.MainWindow;
        if (main != null) {
            if (uri.has_prefix(Components.WebView.CID_URL_PREFIX)) {
                string cid = uri.substring(Components.WebView.CID_URL_PREFIX.length);
                try {
                    Geary.Attachment attachment = this.email.get_attachment_by_content_id(
                        cid
                    );
                    main.attachments.save_attachment.begin(
                        attachment,
                        alt_text,
                        null // XXX no cancellable yet, need UI for it
                    );
                } catch (GLib.Error err) {
                    debug("Could not get attachment \"%s\": %s", cid, err.message);
                }
            } else if (content != null) {
                GLib.File source = GLib.File.new_for_uri(uri);
                // Querying the URL-based file for the display name
                // results in it being looked up, so just get the basename
                // from it directly. GIO seems to decode any %-encoded
                // chars anyway.
                string? display_name = source.get_basename();
                if (Geary.String.is_empty_or_whitespace(display_name)) {
                    display_name = Application.AttachmentManager.untitled_file_name;
                }
                main.attachments.save_buffer.begin(
                    display_name,
                    content,
                    null // XXX no cancellable yet, need UI for it
                );
            }
        }
    }

    private void on_resource_loaded(string id) {
        Gee.Iterator<Geary.Attachment> displayed =
            this.displayed_attachments.iterator();
        while (displayed.has_next()) {
            displayed.next();
            Geary.Attachment? attachment = displayed.get();
            if (attachment.content_id == id) {
                displayed.remove();
            }
        }
    }

    private void on_content_loaded() {
        bool all_loaded = true;
        foreach (ConversationMessage message in this) {
            if (!message.is_content_loaded) {
                all_loaded = false;
                break;
            }
        }
        if (all_loaded && this.message_body_state != COMPLETED) {
            this.message_body_state = COMPLETED;
            this.message_bodies_loaded_lock.blind_notify();

            // Update attachments once the web views have finished
            // loading, since we want to know if any attachments
            // marked as being inline were actually not displayed
            // inline, and hence need to be displayed as if they were
            // attachments.
            this.update_displayed_attachments();
        }
    }

    private void on_service_status_change() {
        if (this.message_body_state == FAILED &&
            !this.load_cancellable.is_cancelled() &&
            is_online()) {
            this.fetch_remote_body.begin();
        }
    }

}
