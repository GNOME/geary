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


    // Displays an attachment's icon and details
    [GtkTemplate (ui = "/org/gnome/Geary/conversation-email-attachment-view.ui")]
    private class AttachmentView : Gtk.Grid {

        public Geary.Attachment attachment { get; private set; }

        [GtkChild]
        private Gtk.Image icon;

        [GtkChild]
        private Gtk.Label filename;

        [GtkChild]
        private Gtk.Label description;

        private string gio_content_type;

        public AttachmentView(Geary.Attachment attachment) {
            this.attachment = attachment;
            string mime_content_type = attachment.content_type.get_mime_type();
            this.gio_content_type = ContentType.from_mime_type(
                mime_content_type
            );

            string? file_name = attachment.content_filename;
            string file_desc = ContentType.get_description(gio_content_type);
            if (ContentType.is_unknown(gio_content_type)) {
                // Translators: This is the file type displayed for
                // attachments with unknown file types.
                file_desc = _("Unknown");
            }
            string file_size = Files.get_filesize_as_string(attachment.filesize);

            if (Geary.String.is_empty(file_name)) {
                // XXX Check for unknown types here and try to guess
                // using attachment data.
                file_name = file_desc;
                file_desc = file_size;
            } else {
                // Translators: The first argument will be a
                // description of the document type, the second will
                // be a human-friendly size string. For example:
                // Document (100.9MB)
                file_desc = _("%s (%s)".printf(file_desc, file_size));
            }
            this.filename.set_text(file_name);
            this.description.set_text(file_desc);
        }

        internal async void load_icon(Cancellable load_cancelled) {
            if (load_cancelled.is_cancelled()) {
                return;
            }

            Gdk.Pixbuf? pixbuf = null;

            // XXX We need to hook up to GtkWidget::style-set and
            // reload the icon when the theme changes.

            int window_scale = get_scale_factor();
            try {
                // If the file is an image, use it. Otherwise get the
                // icon for this mime_type.
                if (this.attachment.content_type.has_media_type("image")) {
                    // Get a thumbnail for the image.
                    // TODO Generate and save the thumbnail when
                    // extracting the attachments rather than when showing
                    // them in the viewer.
                    int preview_size = ATTACHMENT_PREVIEW_SIZE * window_scale;
                    InputStream stream = yield this.attachment.file.read_async(
                        Priority.DEFAULT,
                        load_cancelled
                    );
                    pixbuf = yield new Gdk.Pixbuf.from_stream_at_scale_async(
                        stream, preview_size, preview_size, true, load_cancelled
                    );
                    pixbuf = pixbuf.apply_embedded_orientation();
                } else {
                    // Load the icon for this mime type
                    Icon icon = ContentType.get_icon(this.gio_content_type);
                    Gtk.IconTheme theme = Gtk.IconTheme.get_default();
                    Gtk.IconLookupFlags flags = Gtk.IconLookupFlags.DIR_LTR;
                    if (get_direction() == Gtk.TextDirection.RTL) {
                        flags = Gtk.IconLookupFlags.DIR_RTL;
                    }
                    Gtk.IconInfo? icon_info = theme.lookup_by_gicon_for_scale(
                        icon, ATTACHMENT_ICON_SIZE, window_scale, flags
                    );
                    if (icon_info != null) {
                        pixbuf = yield icon_info.load_icon_async(load_cancelled);
                    }
                }
            } catch (Error error) {
                debug("Failed to load icon for attachment '%s': %s",
                      this.attachment.file.get_path(),
                      error.message);
            }

            if (pixbuf != null) {
                Cairo.Surface surface = Gdk.cairo_surface_create_from_pixbuf(
                    pixbuf, window_scale, get_window()
                );
                this.icon.set_from_surface(surface);
            }
        }

    }


    private const int ATTACHMENT_ICON_SIZE = 32;
    private const int ATTACHMENT_PREVIEW_SIZE = 64;

    private const string ACTION_FORWARD = "forward";
    private const string ACTION_MARK_READ = "mark_read";
    private const string ACTION_MARK_UNREAD = "mark_unread";
    private const string ACTION_MARK_UNREAD_DOWN = "mark_unread_down";
    private const string ACTION_TRASH_MESSAGE = "trash_msg";
    private const string ACTION_DELETE_MESSAGE = "delete_msg";
    private const string ACTION_OPEN_ATTACHMENTS = "open_attachments";
    private const string ACTION_PRINT = "print";
    private const string ACTION_REPLY_SENDER = "reply_sender";
    private const string ACTION_REPLY_ALL = "reply_all";
    private const string ACTION_SAVE_ATTACHMENTS = "save_attachments";
    private const string ACTION_SAVE_ALL_ATTACHMENTS = "save_all_attachments";
    private const string ACTION_SELECT_ALL_ATTACHMENTS = "select_all_attachments";
    private const string ACTION_STAR = "star";
    private const string ACTION_UNSTAR = "unstar";
    private const string ACTION_VIEW_SOURCE = "view_source";

    private const string MANUAL_READ_CLASS = "geary-manual-read";
    private const string SENT_CLASS = "geary-sent";
    private const string STARRED_CLASS = "geary-starred";
    private const string UNREAD_CLASS = "geary-unread";

    /**
     * The specific email that is displayed by this view.
     *
     * This object is updated as additional fields are loaded, so it
     * should not be relied on to a) contain required fields without
     * testing or b) assumed to be the same over the life of this view
     * object.
     */
    public Geary.Email email { get; private set; }

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

    /** Views for attached messages. */
    public Gee.List<ConversationMessage> attached_messages {
        owned get { return this._attached_messages.read_only_view; }
    }
    private Gee.List<ConversationMessage> _attached_messages =
        new Gee.LinkedList<ConversationMessage>();

    /** Determines the message body loading state. */
    public LoadState message_body_state { get; private set; default = NOT_STARTED; }

    // Store from which to load message content, if needed
    private Geary.App.EmailStore email_store;

    // Store from which to lookup contacts
    private Geary.ContactStore contact_store;

    // Store from which to load avatars
    private Application.AvatarStore avatar_store;

    // Cancellable to use when loading message content
    private GLib.Cancellable load_cancellable;

    private Configuration config;

    private Geary.TimeoutManager body_loading_timeout;


    /** Determines if all message's web views have finished loading. */
    private Geary.Nonblocking.Spinlock message_bodies_loaded_lock =
        new Geary.Nonblocking.Spinlock();

    // Message view with selected text, if any
    private ConversationMessage? body_selection_message = null;

    // A subset of the message's attachments that are displayed in the
    // attachments view
    private Gee.List<Geary.Attachment> displayed_attachments =
         new Gee.LinkedList<Geary.Attachment>();

    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    [GtkChild]
    private Gtk.Grid actions;

    [GtkChild]
    private Gtk.Button attachments_button;

    [GtkChild]
    private Gtk.Button star_button;

    [GtkChild]
    private Gtk.Button unstar_button;

    [GtkChild]
    private Gtk.MenuButton email_menubutton;

    [GtkChild]
    private Gtk.InfoBar draft_infobar;

    [GtkChild]
    private Gtk.InfoBar not_saved_infobar;

    [GtkChild]
    private Gtk.Grid sub_messages;

    [GtkChild]
    private Gtk.Grid attachments;

    [GtkChild]
    private Gtk.FlowBox attachments_view;

    [GtkChild]
    private Gtk.Button select_all_attachments;

    private Gtk.Menu attachments_menu;

    private Menu email_menu;
    private Menu email_menu_model;
    private Menu email_menu_trash;
    private Menu email_menu_delete;
    private bool shift_key_down;


    /** Fired when an error occurs loading the message body. */
    public signal void load_error(GLib.Error err);

    /** Fired when the user clicks "reply" in the message menu. */
    public signal void reply_to_message();

    /** Fired when the user clicks "reply all" in the message menu. */
    public signal void reply_all_message();

    /** Fired when the user clicks "forward" in the message menu. */
    public signal void forward_message();

    /** Fired when the user updates the email's flags. */
    public signal void mark_email(
        Geary.NamedFlag? to_add, Geary.NamedFlag? to_remove
    );

    /** Fired when the user updates flags for this email and all others down. */
    public signal void mark_email_from_here(
        Geary.NamedFlag? to_add, Geary.NamedFlag? to_remove
    );

    /** Fired when the user clicks "trash" in the message menu. */
    public signal void trash_message();

    /** Fired when the user clicks "delete" in the message menu. */
    public signal void delete_message();

    /** Fired when the user activates an attachment. */
    public signal void attachments_activated(
        Gee.Collection<Geary.Attachment> attachments
    );

    /** Fired when the user saves an attachment. */
    public signal void save_attachments(
        Gee.Collection<Geary.Attachment> attachments
    );

    /** Fired the edit draft button is clicked. */
    public signal void edit_draft();

    /** Fired when the view source action is activated. */
    public signal void view_source();

    /** Fired when a internal link is activated */
    public signal void internal_link_activated(int y);

    /** Fired when the user selects text in a message. */
    internal signal void body_selection_changed(bool has_selection);


    /**
     * Constructs a new view to display an email.
     *
     * This method sets up most of the user interface for displaying
     * the complete email, but does not attempt any possibly
     * long-running loading processes.
     */
    public ConversationEmail(Geary.Email email,
                             Geary.App.EmailStore email_store,
                             Application.AvatarStore avatar_store,
                             Configuration config,
                             bool is_sent,
                             bool is_draft,
                             GLib.Cancellable load_cancellable) {
        base_ref();
        this.email = email;
        this.is_draft = is_draft;
        this.email_store = email_store;
        this.contact_store = email_store.account.get_contact_store();
        this.avatar_store = avatar_store;
        this.config = config;
        this.load_cancellable = load_cancellable;

        if (is_sent) {
            get_style_context().add_class(SENT_CLASS);
        }

        add_action(ACTION_FORWARD).activate.connect(() => {
                forward_message();
            });
        add_action(ACTION_PRINT).activate.connect(() => {
                print.begin();
            });
        add_action(ACTION_MARK_READ).activate.connect(() => {
                mark_email(null, Geary.EmailFlags.UNREAD);
            });
        add_action(ACTION_MARK_UNREAD).activate.connect(() => {
                mark_email(Geary.EmailFlags.UNREAD, null);
            });
        add_action(ACTION_MARK_UNREAD_DOWN).activate.connect(() => {
                mark_email_from_here(Geary.EmailFlags.UNREAD, null);
            });
        add_action(ACTION_TRASH_MESSAGE).activate.connect(() => {
                trash_message();
            });
        add_action(ACTION_DELETE_MESSAGE).activate.connect(() => {
                delete_message();
            });
        add_action(ACTION_OPEN_ATTACHMENTS, false).activate.connect(() => {
                attachments_activated(get_selected_attachments());
            });
        add_action(ACTION_REPLY_ALL).activate.connect(() => {
                reply_all_message();
            });
        add_action(ACTION_REPLY_SENDER).activate.connect(() => {
                reply_to_message();
            });
        add_action(ACTION_SAVE_ATTACHMENTS, false).activate.connect(() => {
                save_attachments(get_selected_attachments());
            });
        add_action(ACTION_SAVE_ALL_ATTACHMENTS).activate.connect(() => {
                save_attachments(this.displayed_attachments);
            });
        add_action(ACTION_SELECT_ALL_ATTACHMENTS, false).activate.connect(() => {
                this.attachments_view.select_all();
            });
        add_action(ACTION_STAR).activate.connect(() => {
                mark_email(Geary.EmailFlags.FLAGGED, null);
            });
        add_action(ACTION_UNSTAR).activate.connect(() => {
                mark_email(null, Geary.EmailFlags.FLAGGED);
            });
        add_action(ACTION_VIEW_SOURCE).activate.connect(() => {
                view_source();
            });
        insert_action_group("eml", message_actions);

        // Construct the view for the primary message, hook into it

        bool load_images = email.load_remote_images().is_certain();
        Geary.Contact contact = this.contact_store.get_by_rfc822(
            email.get_primary_originator()
        );
        if (contact != null)  {
            load_images |= contact.always_load_remote_images();
        }

        this.primary_message = new ConversationMessage.from_email(
            email, load_images, config
        );
        connect_message_view_signals(this.primary_message);

        this.primary_message.summary.add(this.actions);

        // Wire up the rest of the UI

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-email-menus.ui"
        );
        this.email_menu = new Menu();
        this.email_menu_model = (Menu) builder.get_object("email_menu");
        this.email_menu_trash = (Menu) builder.get_object("email_menu_trash");
        this.email_menu_delete = (Menu) builder.get_object("email_menu_delete");
        this.email_menubutton.set_menu_model(this.email_menu);
        this.email_menubutton.set_sensitive(false);
        this.email_menubutton.toggled.connect(this.on_email_menu);

        this.attachments_menu = new Gtk.Menu.from_model(
            (MenuModel) builder.get_object("attachments_menu")
        );
        this.attachments_menu.attach_to_widget(this, null);

        this.primary_message.infobars.add(this.draft_infobar);
        if (is_draft) {
            this.draft_infobar.show();
            this.draft_infobar.response.connect((infobar, response_id) => {
                    if (response_id == 1) { edit_draft(); }
                });
        }

        this.primary_message.infobars.add(this.not_saved_infobar);

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
     * Loads the avatar for the primary message.
     */
    public async void load_avatar(Application.AvatarStore store)
        throws GLib.Error {
        try {
            yield this.primary_message.load_avatar(store, this.load_cancellable);
        } catch (IOError.CANCELLED err) {
            // okay
        } catch (Error err) {
            Geary.RFC822.MailboxAddress? from = this.email.get_primary_originator();
            debug("Avatar load failed for \"%s\": %s",
                  from != null ? from.to_string() : "<unknown>", err.message);
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
     * Enables or disables actions that require folder support.
     */
    public void set_folder_actions_enabled(bool supports_trash, bool supports_delete) {
        set_action_enabled(ACTION_TRASH_MESSAGE, supports_trash);
        set_action_enabled(ACTION_DELETE_MESSAGE, supports_delete);
    }

    /**
     * Substitutes the "Delete Message" button for the "Move Message to Trash"
     * button if the Shift key is pressed.
     */
    public void shift_key_changed(bool pressed) {
        this.shift_key_down = pressed;
        this.on_email_menu();
    }

    /**
     * Shows the complete message: headers, body and attachments.
     */
    public void expand_email(bool include_transitions=true) {
        this.is_collapsed = false;
        update_email_state();
        this.attachments_button.set_sensitive(true);
        this.email_menubutton.set_sensitive(true);
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
                   yield this.body_selection_message.web_view.get_selection_for_quoting();
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
                   yield this.body_selection_message.web_view.get_selection_for_find();
            } catch (Error err) {
                debug("Failed to get selection for find: %s", err.message);
            }
        }
        return selection;
    }

    /**
     * Returns a new Iterable over all message views in this email view
     */
    internal Gee.Iterator<ConversationMessage> iterator() {
        return new MessageViewIterator(this);
    }

    private SimpleAction add_action(string name, bool enabled = true) {
        SimpleAction action = new SimpleAction(name, null);
        action.set_enabled(enabled);
        message_actions.add_action(action);
        return action;
    }

    private bool get_action_enabled(string name) {
        SimpleAction? action =
            this.message_actions.lookup_action(name) as SimpleAction;
        if (action != null) {
            return action.get_enabled();
        } else {
            return false;
        }
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action =
            this.message_actions.lookup_action(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private void connect_message_view_signals(ConversationMessage view) {
        view.flag_remote_images.connect(on_flag_remote_images);
        view.remember_remote_images.connect(on_remember_remote_images);
        view.internal_link_activated.connect((y) => {
                internal_link_activated(y);
            });
        view.web_view.internal_resource_loaded.connect(on_resource_loaded);
        view.web_view.content_loaded.connect(on_content_loaded);
        view.web_view.selection_changed.connect((has_selection) => {
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

        this.primary_message.web_view.add_internal_resources(cid_resources);
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
                    sub_message, false, this.config
                );
            connect_message_view_signals(attached_message);
            attached_message.web_view.add_internal_resources(cid_resources);
            this.sub_messages.add(attached_message);
            this._attached_messages.add(attached_message);
            attached_message.load_avatar.begin(
                this.avatar_store, this.load_cancellable
            );
            yield attached_message.load_message_body(
                sub_message, this.load_cancellable
            );
            if (!this.is_collapsed) {
                attached_message.show_message_body(false);
            }
        }
    }

    private void update_email_state() {
        Geary.EmailFlags? flags = this.email.email_flags;
        Gtk.StyleContext style = get_style_context();

        bool is_unread = (flags != null && flags.is_unread());
        set_action_enabled(ACTION_MARK_READ, is_unread);
        set_action_enabled(ACTION_MARK_UNREAD, !is_unread);
        set_action_enabled(ACTION_MARK_UNREAD_DOWN, !is_unread);
        if (is_unread) {
            style.add_class(UNREAD_CLASS);
        } else {
            style.remove_class(UNREAD_CLASS);
        }

        bool is_flagged = (flags != null && flags.is_flagged());
        set_action_enabled(ACTION_STAR, !this.is_collapsed && !is_flagged);
        set_action_enabled(ACTION_UNSTAR, !this.is_collapsed && is_flagged);
        if (is_flagged) {
            style.add_class(STARRED_CLASS);
            star_button.hide();
            unstar_button.show();
        } else {
            style.remove_class(STARRED_CLASS);
            star_button.show();
            unstar_button.hide();
        }

        if (flags != null && flags.is_outbox_sent()) {
            this.not_saved_infobar.show();
        }
    }

    private void update_displayed_attachments() {
        bool has_attachments = !this.displayed_attachments.is_empty;
        this.attachments_button.set_visible(has_attachments);
        if (has_attachments) {
            this.primary_message.body_container.add(this.attachments);

            if (this.displayed_attachments.size > 1) {
                this.select_all_attachments.show();
                set_action_enabled(ACTION_SELECT_ALL_ATTACHMENTS, true);
            }

            foreach (Geary.Attachment attachment in this.displayed_attachments) {
                AttachmentView view = new AttachmentView(attachment);
                this.attachments_view.add(view);
                view.load_icon.begin(this.load_cancellable);
            }
        }
    }

    internal Gee.Collection<Geary.Attachment> get_selected_attachments() {
        Gee.LinkedList<Geary.Attachment> selected =
            new Gee.LinkedList<Geary.Attachment>();
        foreach (Gtk.FlowBoxChild child in
                 this.attachments_view.get_selected_children()) {
            selected.add(((AttachmentView) child.get_child()).attachment);
        }
        return selected;
    }

    private void handle_load_failure(GLib.Error err) {
        load_error(err);
        this.message_body_state = FAILED;
        this.primary_message.show_load_error_pane();
    }

    private void handle_load_offline() {
        this.message_body_state = FAILED;
        this.primary_message.show_offline_pane();
    }

    private inline bool is_online() {
        return (this.email_store.account.incoming.current_status == CONNECTED);
    }

    /**
     * Updates the email menu if it is open.
     */
    private void on_email_menu() {
        if (this.email_menubutton.active) {
            this.email_menu.remove_all();

            bool supports_trash = get_action_enabled(ACTION_TRASH_MESSAGE);
            bool supports_delete = get_action_enabled(ACTION_DELETE_MESSAGE);
            bool show_trash_button = !this.shift_key_down && (supports_trash || !supports_delete);
            GtkUtil.menu_foreach(this.email_menu_model, (label, name, target, section) => {
                if ((section != this.email_menu_trash || show_trash_button) &&
                    (section != this.email_menu_delete || !show_trash_button)) {
                    this.email_menu.append_item(new MenuItem.section(label, section));
                }
            });
        }
    }

    private async void print() throws Error {
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
            builder.add_string_value(this.email.date.to_string());
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
        yield this.primary_message.web_view.run_javascript(js, null);

        Gtk.Window? window = get_toplevel() as Gtk.Window;
        WebKit.PrintOperation op = new WebKit.PrintOperation(
            this.primary_message.web_view
        );
        Gtk.PrintSettings settings = new Gtk.PrintSettings();

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

    private void on_body_loading_timeout() {
        this.primary_message.show_loading_pane();
    }

    private void on_load_cancelled() {
        this.body_loading_timeout.reset();
    }

    private void on_flag_remote_images(ConversationMessage view) {
        // XXX check we aren't already auto loading the image
        mark_email(Geary.EmailFlags.LOAD_REMOTE_IMAGES, null);
    }


    private void on_remember_remote_images(ConversationMessage view) {
        Geary.RFC822.MailboxAddress? sender = this.email.get_primary_originator();
        if (sender != null) {
            Geary.Contact? contact = this.contact_store.get_by_rfc822(sender);
            if (contact != null) {
                Geary.ContactFlags flags = new Geary.ContactFlags();
                flags.add(Geary.ContactFlags.ALWAYS_LOAD_REMOTE_IMAGES);
                this.contact_store.mark_contacts_async.begin(
                    Geary.Collection.single(contact), flags, null
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
            if (!message.web_view.is_content_loaded) {
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

    [GtkCallback]
    private void on_attachments_child_activated(Gtk.FlowBox view,
                                                Gtk.FlowBoxChild child) {
        attachments_activated(
            Geary.iterate<Geary.Attachment>(
                ((AttachmentView) child.get_child()).attachment
            ).to_array_list()
        );
    }

    [GtkCallback]
    private void on_attachments_selected_changed(Gtk.FlowBox view) {
        uint len = view.get_selected_children().length();
        bool not_empty = len > 0;
        set_action_enabled(ACTION_OPEN_ATTACHMENTS, not_empty);
        set_action_enabled(ACTION_SAVE_ATTACHMENTS, not_empty);
        set_action_enabled(ACTION_SELECT_ALL_ATTACHMENTS,
                           len < this.displayed_attachments.size);
    }

    private void on_service_status_change() {
        if (this.message_body_state == FAILED &&
            !this.load_cancellable.is_cancelled() &&
            is_online()) {
            this.fetch_remote_body.begin();
        }
    }

}
