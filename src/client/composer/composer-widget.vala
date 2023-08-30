/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2017-2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private errordomain AttachmentError {
    FILE,
    DUPLICATE
}

/**
 * A widget for editing an email message.
 *
 * Composers must always be placed in an instance of {@link
 * Container}.
 */
[GtkTemplate (ui = "/org/gnome/Geary/composer-widget.ui")]
public class Composer.Widget : Gtk.EventBox, Geary.BaseInterface {


    /**
     * The email fields the composer requires for context email.
     *
     * @see load_context
     */
    public const Geary.Email.Field REQUIRED_FIELDS = ENVELOPE | HEADER | BODY;

    /// Translators: Title for an empty composer window
    private const string DEFAULT_TITLE = _("New Message");

    /**
     * Determines the type of the context email passed to the composer
     *
     * @see context_type
     * @see load_context
     */
    public enum ContextType {
        /** No context mail was provided. */
        NONE,

        /** Context is an email to edited, for example a draft or template. */
        EDIT,

        /** Context is an email being replied to the sender only. */
        REPLY_SENDER,

        /** Context is an email being replied to all recipients. */
        REPLY_ALL,

        /** Context is an email being forwarded. */
        FORWARD
    }

    /**
     * Determines the result of prompting whether to close the composer.
     *
     * @see conditional_close
     */
    public enum CloseStatus {

        /** The composer is already closed. */
        CLOSED,

        /** The composer is ready to be closed, but is not yet. */
        READY,

        /** Closing the composer was not confirmed by a human. */
        CANCELLED;

    }

    /** Defines different supported user interface modes. */
    public enum PresentationMode {

        /** Composer has been closed. */
        CLOSED,

        /** Composer is not currently visible. */
        NONE,

        /**
         * Composer is in its own window, not in a main windows.
         *
         * @see Window
         */
        DETACHED,

        /**
         * Composer is in a full-height box in a main window.
         *
         * @see Box
         */
        PANED,

        /**
         * Composer is embedded inline in a conversation.
         *
         * @see Embed
         */
        INLINE,

        /**
         * Composer is embedded inline with header fields hidden.
         *
         * @see Embed
         */
        INLINE_COMPACT;

    }

    private enum AttachPending { ALL, INLINE_ONLY }

    private enum DraftPolicy { DISCARD, KEEP }

    private class HeaderRow<T> : Gtk.Box, Geary.BaseInterface {


        static construct {
            set_css_name("geary-composer-widget-header-row");
        }

        public Gtk.Label label { get; private set; }
        public Gtk.Box value_container { get; private set; }
        public T value { get; private set; }


        public HeaderRow(string label, T value) {
            Object(orientation: Gtk.Orientation.HORIZONTAL);
            base_ref();

            this.label = new Gtk.Label(label);
            this.label.use_underline = true;
            this.label.xalign = 1.0f;
            add(this.label);

            this.value_container = new Gtk.Box(HORIZONTAL, 0);
            this.value_container.get_style_context().add_class("linked");
            add(this.value_container);

            this.value = value;

            var value_widget = value as Gtk.Widget;
            if (value_widget != null) {
                value_widget.hexpand = true;
                this.value_container.add(value_widget);
                this.label.set_mnemonic_widget(value_widget);
            }

            show_all();
        }

        ~HeaderRow() {
            base_unref();
        }

    }

    private class EntryHeaderRow<T> : HeaderRow<T> {


        public Components.EntryUndo? undo { get; private set; }


        public EntryHeaderRow(string label, T value) {
            base(label, value);
            var value_entry = value as Gtk.Entry;
            if (value_entry != null) {
                this.undo = new Components.EntryUndo(value_entry);
            }
        }

    }

    private class FromAddressMap {
        public Application.AccountContext account;
        public Geary.RFC822.MailboxAddresses from;
        public FromAddressMap(Application.AccountContext account,
                              Geary.RFC822.MailboxAddresses from) {
            this.account = account;
            this.from = from;
        }
    }

    // XXX need separate composer close action in addition to the
    // default window close action so we can bind Esc to it without
    // also binding the default window close action to Esc as
    // well. This could probably be fixed by pulling both the main
    // window's and composer's actions out of the 'win' action
    // namespace, leaving only common window actions there.
    private const string ACTION_ADD_ATTACHMENT = "add-attachment";
    private const string ACTION_ADD_ORIGINAL_ATTACHMENTS = "add-original-attachments";
    private const string ACTION_CLOSE = "composer-close";
    private const string ACTION_CUT = "cut";
    private const string ACTION_DETACH = "detach";
    private const string ACTION_DISCARD = "discard";
    private const string ACTION_PASTE = "paste";
    private const string ACTION_SEND = "send";
    private const string ACTION_SHOW_EXTENDED_HEADERS = "show-extended-headers";

    private const ActionEntry[] ACTIONS = {
        { Action.Edit.COPY,                on_copy                          },
        { Action.Window.CLOSE,             on_close                         },
        { Action.Window.SHOW_HELP_OVERLAY, on_show_help_overlay             },
        { Action.Window.SHOW_MENU,         on_show_window_menu              },
        { ACTION_ADD_ATTACHMENT,           on_add_attachment                },
        { ACTION_ADD_ORIGINAL_ATTACHMENTS, on_pending_attachments           },
        { ACTION_CLOSE,                    on_close                         },
        { ACTION_CUT,                      on_cut                           },
        { ACTION_DETACH,                   on_detach                        },
        { ACTION_DISCARD,                  on_discard                       },
        { ACTION_PASTE,                    on_paste                         },
        { ACTION_SEND,                     on_send                          },
        { ACTION_SHOW_EXTENDED_HEADERS,    on_toggle_action, null, "false",
                                           on_show_extended_headers_toggled },
    };


    static construct {
        set_css_name("geary-composer-widget");
    }

    public static void add_accelerators(Application.Client application) {
        application.add_window_accelerators(ACTION_DISCARD, { "Escape" } );
        application.add_window_accelerators(ACTION_ADD_ATTACHMENT, { "<Ctrl>t" } );
        application.add_window_accelerators(ACTION_DETACH, { "<Ctrl>d" } );
        application.add_window_accelerators(ACTION_CUT, { "<Ctrl>x" } );
        application.add_window_accelerators(ACTION_PASTE, { "<Ctrl>v" } );
    }

    private const string DRAFT_SAVED_TEXT = _("Saved");
    private const string DRAFT_SAVING_TEXT = _("Saving");
    private const string DRAFT_ERROR_TEXT = _("Error saving");
    private const string BACKSPACE_TEXT = _("Press Backspace to delete quote");

    private const string URI_LIST_MIME_TYPE = "text/uri-list";
    private const string FILE_URI_PREFIX = "file://";

    private const string MAILTO_URI_PREFIX = "mailto:";

    // Keep these in sync with the next const below.
    private const string ATTACHMENT_KEYWORDS =
        "attach|attaching|attaches|attachment|attachments|attached|enclose|enclosed|enclosing|encloses|enclosure|enclosures";
    // Translators: This is list of keywords, separated by pipe ("|")
    // characters, that suggest an attachment; since this is full-word
    // checking, include all variants of each word. No spaces are
    // allowed. The words will be converted to lower case based on
    // locale and English versions included automatically.
    private const string ATTACHMENT_KEYWORDS_LOCALISED =
        _("attach|attaching|attaches|attachment|attachments|attached|enclose|enclosed|enclosing|encloses|enclosure|enclosures");

    private const string PASTED_IMAGE_FILENAME_TEMPLATE = "geary-pasted-image-%u.png";

    /** The account the email is being sent from. */
    public Application.AccountContext sender_context { get; private set; }

    /** The identifier of the saved email this composer holds, if any. */
    public Geary.EmailIdentifier? saved_id {
        get; private set; default = null;
    }

    /** Determines the type of the context email. */
    public ContextType context_type { get; private set; default = NONE; }

    /** Determines the composer's current presentation mode. */
    public PresentationMode current_mode { get; set; default = NONE; }

    /** Determines if the composer is completely empty. */
    public bool is_blank {
        get {
            return this.to_row.value.is_empty
                && this.cc_row.value.is_empty
                && this.bcc_row.value.is_empty
                && this.reply_to_row.value.is_empty
                && this.subject_row.value.buffer.length == 0
                && this.editor.body.is_empty
                && this.attached_files.size == 0;
        }
    }

    /** The email body editor widget. */
    public Editor editor { get; private set; }

    /**
     * The last focused text input widget.
     *
     * This may be a Gtk.Entry if an address field or the subject was
     * most recently focused, or the {@link editor} if the body was
     * most recently focused.
     */
    public Gtk.Widget? focused_input_widget { get; private set; default = null; }

    /** Determines if the composer can send the message. */
    public bool can_send {
        get {
            return this._can_send;
        }
        set {
            this._can_send = value;
            validate_send_button();
        }
    }
    private bool _can_send = true;

    /** Currently selected sender mailbox. */
    public Geary.RFC822.MailboxAddresses from { get; private set; }

    /** Current text of the `to` entry. */
    public string to {
        get { return this.to_row.value.get_text(); }
        private set { this.to_row.value.set_text(value); }
    }

    /** Current text of the `cc` entry. */
    public string cc {
        get { return this.cc_row.value.get_text(); }
        private set { this.cc_row.value.set_text(value); }
    }

    /** Current text of the `bcc` entry. */
    public string bcc {
        get { return this.bcc_row.value.get_text(); }
        private set { this.bcc_row.value.set_text(value); }
    }

    /** Current text of the `reply-to` entry. */
    public string reply_to {
        get { return this.reply_to_row.value.get_text(); }
        private set { this.reply_to_row.value.set_text(value); }
    }

    /** Current text of the `sender` entry. */
    public string subject {
        get { return this.subject_row.value.get_text(); }
        private set { this.subject_row.value.set_text(value); }
    }

    /** The In-Reply-To header value for the composed email, if any. */
    public Geary.RFC822.MessageIDList in_reply_to {
        get; private set; default = new Geary.RFC822.MessageIDList();
    }

    /** The References header value for the composed email, if any. */
    public Geary.RFC822.MessageIDList references {
        get; private set; default = new Geary.RFC822.MessageIDList();
    }

    /** Overrides for the draft folder as save destination, if any. */
    internal Geary.Folder? save_to { get; private set; default = null; }

    internal Headerbar header { get; private set; }

    internal bool has_multiple_from_addresses {
        get {
            return (
                this.application.get_account_contexts().size > 1 ||
                this.sender_context.account.information.has_sender_aliases
            );
        }
    }

    [GtkChild] private unowned Gtk.Box header_container;
    [GtkChild] private unowned Gtk.Grid editor_container;

    [GtkChild] private unowned Gtk.Grid email_headers;
    [GtkChild] private unowned Gtk.Box filled_headers;
    [GtkChild] private unowned Gtk.Revealer extended_headers_revealer;
    [GtkChild] private unowned Gtk.Box extended_headers;
    [GtkChild] private unowned Gtk.ToggleButton show_extended_headers;

    private Gee.ArrayList<FromAddressMap> from_list = new Gee.ArrayList<FromAddressMap>();

    private Gtk.SizeGroup header_labels_group = new Gtk.SizeGroup(HORIZONTAL);

    private HeaderRow<Gtk.ComboBoxText> from_row;
    private HeaderRow<EmailEntry> to_row;
    private HeaderRow<EmailEntry> cc_row;
    private HeaderRow<EmailEntry> bcc_row;
    private HeaderRow<EmailEntry> reply_to_row;
    private HeaderRow<Gtk.Entry> subject_row;

    private Gspell.Checker subject_spell_checker = new Gspell.Checker(null);
    private Gspell.Entry subject_spell_entry;

    [GtkChild] private unowned Gtk.Box attachments_box;
    [GtkChild] private unowned Gtk.Box hidden_on_attachment_drag_over;
    [GtkChild] private unowned Gtk.Box visible_on_attachment_drag_over;
    [GtkChild] private unowned Gtk.Widget hidden_on_attachment_drag_over_child;
    [GtkChild] private unowned Gtk.Widget visible_on_attachment_drag_over_child;

    private GLib.SimpleActionGroup actions = new GLib.SimpleActionGroup();

    /** Determines if the composer can currently save a draft. */
    private bool can_save {
        get { return this.draft_manager != null; }
    }

    /** Determines if current message should be saved as draft. */
    private bool should_save {
        get {
            return this.can_save
                && !this.is_draft_saved
                && !this.is_blank;
        }
    }

    private bool is_attachment_overlay_visible = false;
    private bool top_posting = true;

    // The message(s) this email is in reply to/forwarded from
    private Gee.Set<Geary.EmailIdentifier> referred_ids =
        new Gee.HashSet<Geary.EmailIdentifier>();

    private Gee.List<Geary.Attachment>? pending_attachments = null;
    private AttachPending pending_include = AttachPending.INLINE_ONLY;
    private Gee.Set<File> attached_files = new Gee.HashSet<File>(Geary.Files.nullable_hash,
        Geary.Files.nullable_equal);
    private Gee.Map<string,Geary.Memory.Buffer> inline_files = new Gee.HashMap<string,Geary.Memory.Buffer>();
    private Gee.Map<string,Geary.Memory.Buffer> cid_files = new Gee.HashMap<string,Geary.Memory.Buffer>();

    private Geary.App.DraftManager? draft_manager = null;
    private GLib.Cancellable? draft_manager_opening = null;
    private Geary.TimeoutManager draft_timer;
    private bool is_draft_saved = false;
    private string draft_status_text {
        get { return this._draft_status_text; }
        set {
            this._draft_status_text = value;
            update_info_label();
        }
    }
    private string _draft_status_text = "";

    private bool can_delete_quote {
        get { return this._can_delete_quote; }
        set {
            this._can_delete_quote = value;
            update_info_label();
        }
    }
    private bool _can_delete_quote = false;

    private Container? container {
        get { return this.parent as Container; }
    }

    private ApplicationInterface application;

    private Application.Configuration config;


    internal Widget(ApplicationInterface application,
                    Application.Configuration config,
                    Application.AccountContext initial_account,
                    Geary.Folder? save_to = null) {
        components_reflow_box_get_type();
        base_ref();
        this.application = application;
        this.config = config;
        this.sender_context = initial_account;
        this.save_to = save_to;

        this.header = new Headerbar(config);
        this.header.expand_composer.connect(on_expand_compact_headers);
        // Hide until we know we can save drafts
        this.header.show_save_and_close = false;

        // Setup drag 'n drop
        const Gtk.TargetEntry[] target_entries = { { URI_LIST_MIME_TYPE, 0, 0 } };
        Gtk.drag_dest_set(this, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            target_entries, Gdk.DragAction.COPY);

        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK);

        this.visible_on_attachment_drag_over.remove(
            this.visible_on_attachment_drag_over_child
        );

        this.from_row = new HeaderRow<Gtk.ComboBoxText>(
            /// Translators: Label for composer From address entry
            _("_From"), new Gtk.ComboBoxText()
        );
        this.from_row.value.changed.connect(on_envelope_changed);
        var cells = this.from_row.value.get_cells();
        ((Gtk.CellRendererText) cells.data).ellipsize = END;
        this.header_labels_group.add_widget(this.from_row.label);
        this.filled_headers.add(this.from_row);

        this.to_row = new EntryHeaderRow<EmailEntry>(
            /// Translators: Label for composer To address entry
            _("_To"), new EmailEntry(this)
        );
        this.to_row.value_container.add(this.show_extended_headers);
        this.to_row.value.changed.connect(on_envelope_changed);
        this.header_labels_group.add_widget(this.to_row.label);
        this.filled_headers.add(this.to_row);

        this.cc_row = new EntryHeaderRow<EmailEntry>(
            /// Translators: Label for composer CC address entry
            _("_Cc"), new EmailEntry(this)
        );
        this.cc_row.value.changed.connect(on_envelope_changed);
        this.header_labels_group.add_widget(this.cc_row.label);
        this.extended_headers.add(this.cc_row);

        this.bcc_row = new EntryHeaderRow<EmailEntry>(
            /// Translators: Label for composer BCC address entry
            _("_Bcc"), new EmailEntry(this)
        );
        this.bcc_row.value.changed.connect(on_envelope_changed);
        this.header_labels_group.add_widget(this.bcc_row.label);
        this.extended_headers.add(this.bcc_row);

        this.reply_to_row = new EntryHeaderRow<EmailEntry>(
            /// Translators: Label for composer Reply-To address entry
            _("_Reply to"), new EmailEntry(this)
        );
        this.reply_to_row.value.changed.connect(on_envelope_changed);
        this.header_labels_group.add_widget(this.reply_to_row.label);
        this.extended_headers.add(this.reply_to_row);

        this.subject_row = new EntryHeaderRow<Gtk.Entry>(
            /// Translators: Label for composer Subject line entry
            _("_Subject"), new Gtk.Entry()
        );
        this.subject_row.value.changed.connect(on_subject_changed);
        this.header_labels_group.add_widget(this.subject_row.label);
        this.email_headers.add(this.subject_row);

        this.subject_spell_entry = Gspell.Entry.get_from_gtk_entry(
            this.subject_row.value
        );
        config.settings.changed[
            Application.Configuration.SPELL_CHECK_LANGUAGES
        ].connect(() => {
                update_subject_spell_checker();
            });
        update_subject_spell_checker();

        this.editor = new Editor(config);
        this.editor.insert_image.connect(
            (from_clipboard) => {
                if (from_clipboard) {
                    paste_image();
                } else {
                    insert_image();
                }
            }
        );
        this.editor.body.content_loaded.connect(on_content_loaded);
        this.editor.body.document_modified.connect(() => { draft_changed(); });
        this.editor.body.key_press_event.connect(on_editor_key_press_event);
        this.editor.show();
        this.editor_container.add(this.editor);

        // Listen to account signals to update from menu.
        this.application.account_available.connect(
            on_account_available
        );
        this.application.account_unavailable.connect(
            on_account_unavailable
        );

        // Listen for drag and dropped image file
        this.editor.body.image_file_dropped.connect(
            on_image_file_dropped
        );

        // TODO: also listen for account updates to allow adding identities while writing an email

        this.from = new Geary.RFC822.MailboxAddresses.single(
            this.sender_context.account.information.primary_mailbox
        );

        this.draft_timer = new Geary.TimeoutManager.seconds(
            10, on_draft_timeout
        );

        // Add actions once every element has been initialized and added
        // Composer actions
        this.actions.add_action_entries(ACTIONS, this);
        this.actions.change_action_state(
            ACTION_SHOW_EXTENDED_HEADERS, false
        );
        // Main actions use the window prefix so they override main
        // window actions. But for some reason, we can't use the same
        // prefix for the headerbar.
        insert_action_group(Action.Window.GROUP_NAME, this.actions);
        this.header.insert_action_group("cmh", this.actions);
        validate_send_button();

        load_entry_completions();
    }

    ~Widget() {
        base_unref();
    }

    /** Loads an empty message into the composer. */
    public async void load_empty_body(Geary.RFC822.MailboxAddress? to = null)
        throws GLib.Error {
        if (to != null) {
            this.to = to.to_full_display();
            update_extended_headers();
        }
        yield finish_loading("", "", false);
    }

    /** Loads a mailto: URL into the composer. */
    public async void load_mailto(string mailto)
        throws GLib.Error {
        Gee.HashMultiMap<string, string> headers = new Gee.HashMultiMap<string, string>();
        if (mailto.has_prefix(MAILTO_URI_PREFIX)) {
            // Parse the mailto link.
            string? email = null;
            string[] parts = mailto.substring(MAILTO_URI_PREFIX.length).split("?", 2);
            if (parts.length > 0) {
                email = Uri.unescape_string(parts[0]);
            }
            string[] params = parts.length == 2 ? parts[1].split("&") : new string[0];
            foreach (string param in params) {
                string[] param_parts = param.split("=", 2);
                if (param_parts.length == 2) {
                    headers.set(Uri.unescape_string(param_parts[0]).down(),
                        Uri.unescape_string(param_parts[1]));
                }
            }

            // Assemble the headers.
            if (!Geary.String.is_empty_or_whitespace(email) &&
                headers.contains("to")) {
                this.to = "%s,%s".printf(
                    email, Geary.Collection.first(headers.get("to"))
                );
            } else if (!Geary.String.is_empty_or_whitespace(email)) {
                this.to = email;
            } else if (headers.contains("to")) {
                this.to = Geary.Collection.first(headers.get("to"));
            }

            if (headers.contains("cc"))
                this.cc = Geary.Collection.first(headers.get("cc"));

            if (headers.contains("bcc"))
                this.bcc = Geary.Collection.first(headers.get("bcc"));

            if (headers.contains("subject"))
                this.subject = Geary.Collection.first(headers.get("subject"));

            var body = "";
            if (headers.contains("body")) {
                body = Geary.HTML.preserve_whitespace(
                    Geary.HTML.escape_markup(
                        Geary.Collection.first(headers.get("body"))
                    )
                );
            }

            Gee.List<string> attachments = new Gee.LinkedList<string>();
            attachments.add_all(headers.get("attach"));
            attachments.add_all(headers.get("attachment"));
            foreach (string attachment in attachments) {
                try {
                    add_attachment_part(File.new_for_commandline_arg(attachment));
                } catch (Error err) {
                    attachment_failed(err.message);
                }
            }
            yield finish_loading(body, "", false);
            update_extended_headers();
        }
    }

    /**
     * Loads a draft, reply, or forwarded message into the composer.
     *
     * If the given context email does not contain the fields
     * specified by {@link REQUIRED_FIELDS}, it will be loaded from
     * the current account context's store with those.
     */
    public async void load_context(ContextType type,
                                   Geary.Email context,
                                   string? quote)
        throws GLib.Error {
        if (type == NONE) {
            throw new Geary.EngineError.BAD_PARAMETERS(
                "Invalid context type: %s", type.to_string()
            );
        }

        var full_context = context;
        if (!context.fields.is_all_set(REQUIRED_FIELDS)) {
            Gee.Collection<Geary.Email>? email =
                yield this.sender_context.emails.list_email_by_sparse_id_async(
                    Geary.Collection.single(context.id),
                    REQUIRED_FIELDS,
                    NONE,
                    this.sender_context.cancellable
                );
            if (email == null || email.is_empty) {
                throw new Geary.EngineError.INCOMPLETE_MESSAGE(
                    "Unable to load email fields required for composer: %s",
                    context.fields.to_string()
                );
            }
            full_context = Geary.Collection.first(email);
        }

        this.context_type = type;

        if (type == EDIT ||
            type == FORWARD) {
            this.pending_include = AttachPending.ALL;
        }
        this.pending_attachments = full_context.attachments;

        var body = "";
        var complete_quote = "";
        var body_complete = false;
        switch (type) {
        case EDIT:
            this.saved_id = full_context.id;

            if (full_context.from != null) {
                this.from = full_context.from;
            }
            if (full_context.to != null) {
                this.to_row.value.addresses = full_context.to;
            }
            if (full_context.cc != null) {
                this.cc_row.value.addresses = full_context.cc;
            }
            if (full_context.bcc != null) {
                this.bcc_row.value.addresses = full_context.bcc;
            }
            if (full_context.reply_to != null) {
                this.reply_to_row.value.addresses = full_context.reply_to;
            }
            if (full_context.in_reply_to != null) {
                this.in_reply_to = this.in_reply_to.concatenate_list(
                    full_context.in_reply_to
                );
            }
            if (full_context.references != null) {
                this.references = this.references.concatenate_list(
                    full_context.references
                );
            }
            if (full_context.subject != null) {
                this.subject = full_context.subject.value ?? "";
            }
            Geary.RFC822.Message message = full_context.get_message();
            if (message.has_html_body()) {
                body = message.get_html_body(null);
                body_complete = body.contains(
                    "id=\"%s\"".printf(WebView.BODY_HTML_ID)
                );
            } else {
                body = message.get_plain_body(true, null);
            }
            yield restore_reply_to_state();
            break;

        case REPLY_SENDER:
        case REPLY_ALL:
            // Set the preferred from address based on the message
            // being replied to
            if (!update_from_address(full_context.to)) {
                if (!update_from_address(full_context.cc)) {
                    if (!update_from_address(full_context.bcc)) {
                        update_from_address(full_context.from);
                    }
                }
            }
            this.subject = Geary.RFC822.Utils.create_subject_for_reply(
                full_context
            );
            add_recipients_and_ids(type, full_context);
            complete_quote = Util.Email.quote_email_for_reply(
                full_context, quote, HTML
            );
            if (!Geary.String.is_empty(quote)) {
                this.top_posting = false;
            } else {
                this.can_delete_quote = true;
            }
            break;

        case FORWARD:
            this.subject = Geary.RFC822.Utils.create_subject_for_forward(
                full_context
            );
            if (full_context.message_id != null) {
                this.references = this.references.concatenate_id(
                    full_context.message_id
                );
            }
            complete_quote = Util.Email.quote_email_for_forward(
                full_context, quote, HTML
            );
            this.referred_ids.add(full_context.id);
            break;

        case NONE:
            // no-op
            break;
        }
        update_extended_headers();

        yield finish_loading(body, complete_quote, body_complete);
    }

    /**
     * Returns the emails referred to by the composed email.
     *
     * A referred email is the email this composer is a reply to, or
     * forwarded from. There may be multiple if a composer was already
     * open and another email was replied to.
     */
    public Gee.Set<Geary.EmailIdentifier> get_referred_ids() {
        return this.referred_ids.read_only_view;
    }

    /** Detaches the composer and opens it in a new window. */
    public void detach(Application.Client application) {
        Gtk.Widget? focused_widget = null;
        if (this.container != null) {
            focused_widget = this.container.top_window.get_focus();
            this.container.close();
        }

        var new_window = new Window(this, application);

        // Workaround a GTK+ crasher, Bug 771812. When the
        // composer is re-parented, its menu_button's popover
        // keeps a reference to the conversation window's
        // viewport, so when that is removed it has a null parent
        // and we crash. To reproduce: Reply inline, detach the
        // composer, then choose a different conversation back in
        // the main window. The workaround here sets a new menu
        // model and hence the menu_button constructs a new
        // popover.
        this.editor.actions.change_action_state(
            Editor.ACTION_TEXT_FORMAT,
            this.config.compose_as_html ? "html" : "plain"
        );

        set_mode(DETACHED);

        // If the previously focused widget is in the new composer
        // window then focus that, else focus something useful.
        bool refocus = true;
        if (focused_widget != null) {
            Window? focused_window = focused_widget.get_toplevel() as Window;
            if (new_window == focused_window) {
                focused_widget.grab_focus();
                refocus = false;
            }
        }
        if (refocus) {
            set_focus();
        }
    }

    /**
     * Prompts to close the composer if needed, before closing it.
     *
     * If the composer is already closed no action is taken. If the
     * composer is blank then this method will close the composer,
     * else the composer will either be saved or discarded as needed
     * then closed.
     *
     * The return value specifies whether the composer is being closed
     * or if the prompt was cancelled by a human.
     */
    public CloseStatus conditional_close(bool should_prompt,
                                         bool is_shutdown = false) {
        CloseStatus status = CLOSED;
        switch (this.current_mode) {
        case PresentationMode.CLOSED:
            // no-op
            break;

        case PresentationMode.NONE:
            status = READY;
            break;

        default:
            if (this.is_blank) {
                this.close.begin();
                // This may be a bit of a lie but will very soon
                // become true.
                status = CLOSED;
            } else if (should_prompt) {
                present();
                if (this.can_save) {
                    var dialog = new TernaryConfirmationDialog(
                        this.container.top_window,
                        // Translators: This dialog text is displayed to the
                        // user when closing a composer where the options are
                        // Keep, Discard or Cancel.
                        _("Do you want to keep or discard this draft message?"),
                        null,
                        Stock._KEEP,
                        Stock._DISCARD, Gtk.ResponseType.CLOSE,
                        "",
                        is_shutdown ? "destructive-action" : "",
                        Gtk.ResponseType.OK // Default == Keep
                    );
                    Gtk.ResponseType response = dialog.run();
                    if (response == CANCEL ||
                        response == DELETE_EVENT) {
                        // Cancel
                        status = CANCELLED;
                    } else if (response == OK) {
                        // Keep
                        this.save_and_close.begin();
                    } else {
                        // Discard
                        this.discard_and_close.begin();
                    }
                } else {
                    AlertDialog dialog = new ConfirmationDialog(
                        container.top_window,
                        // Translators: This dialog text is displayed to the
                        // user when closing a composer where the options are
                        // only Discard or Cancel.
                        _("Do you want to discard this draft message?"),
                        null,
                        Stock._DISCARD,
                        ""
                    );
                    Gtk.ResponseType response = dialog.run();
                    if (response == OK) {
                        this.discard_and_close.begin();
                    } else {
                        status = CANCELLED;
                    }
                }
            } else if (this.can_save) {
                this.save_and_close.begin();
            } else {
                this.discard_and_close.begin();
            }
            break;
        }

        return status;
    }

    /**
     * Closes the composer and any drafts unconditionally.
     *
     * This method disables the composer, closes the draft manager,
     * then destroys the composer itself.
     */
    public async void close() {
        if (this.current_mode != CLOSED) {
            // this will set current_mode to NONE first
            set_enabled(false);
            this.current_mode = CLOSED;

            if (this.draft_manager_opening != null) {
                this.draft_manager_opening.cancel();
                this.draft_manager_opening = null;
            }

            try {
                yield close_draft_manager(KEEP);
            } catch (GLib.Error error) {
                this.application.report_problem(
                    new Geary.AccountProblemReport(
                        this.sender_context.account.information, error
                    )
                );
            }

            destroy();
        }
    }

    public override void destroy() {
        if (this.draft_manager != null) {
            warning("Draft manager still open on composer destroy");
        }

        this.application.account_available.disconnect(
            on_account_available
        );
        this.application.account_unavailable.disconnect(
            on_account_unavailable
        );
        base.destroy();
    }

    /**
     * Sets whether the composer is able to be used.
     *
     * If disabled, the composer hidden, detached from its container
     * and will stop periodically saving drafts.
     */
    public void set_enabled(bool enabled) {
        this.current_mode = NONE;
        this.set_sensitive(enabled);

        // Need to update this separately since it may be detached
        // from the widget itself.
        this.header.set_sensitive(enabled);

        if (enabled) {
            var current_account = this.sender_context.account;
            this.open_draft_manager.begin(
                this.saved_id,
                (obj, res) => {
                    try {
                        this.open_draft_manager.end(res);
                    } catch (GLib.Error error) {
                        this.application.report_problem(
                            new Geary.AccountProblemReport(
                                current_account.information, error
                            )
                        );
                    }
                }
            );
        } else {
            if (this.container != null) {
                this.container.close();
            }
            this.draft_timer.reset();
        }
    }

    /** Overrides the folder used for saving drafts. */
    public void set_save_to_override(Geary.Folder? save_to) {
        this.save_to = save_to;
        this.reopen_draft_manager.begin();
    }

    /**
     * Loads and sets contact auto-complete data for the current account.
     */
    private void load_entry_completions() {
        Application.ContactStore contacts = this.sender_context.contacts;
        this.to_row.value.completion = new ContactEntryCompletion(contacts);
        this.cc_row.value.completion = new ContactEntryCompletion(contacts);
        this.bcc_row.value.completion = new ContactEntryCompletion(contacts);
        this.reply_to_row.value.completion = new ContactEntryCompletion(contacts);
    }

    /**
     * Restores the composer's widget state from any replied to messages.
     */
    private async void restore_reply_to_state() {
        Gee.List<Geary.RFC822.MailboxAddress> sender_addresses =
            this.sender_context.account.information.sender_mailboxes;
        var to_addresses = new Geary.RFC822.MailboxAddresses();
        var cc_addresses = new Geary.RFC822.MailboxAddresses();

        bool new_email = true;
        foreach (var mid in this.in_reply_to) {
            Gee.MultiMap<Geary.Email, Geary.FolderPath?>? email_map = null;
            try {
                // TODO: Folder blacklist
                email_map = yield this.sender_context.account
                    .local_search_message_id_async(
                        mid,
                        ENVELOPE,
                        true,
                        null,
                        new Geary.EmailFlags.with(Geary.EmailFlags.DRAFT)
                    );
            } catch (GLib.Error error) {
                warning(
                    "Error restoring edited message state from In-Reply-To: %s",
                    error.message
                );
            }
            if (email_map != null) {
                foreach (var candidate in email_map.get_keys()) {
                    if (candidate.message_id != null &&
                        mid.equal_to(candidate.message_id)) {
                        to_addresses = to_addresses.merge_list(
                            Geary.RFC822.Utils.create_to_addresses_for_reply(
                                candidate, sender_addresses
                            )
                        );
                        cc_addresses = cc_addresses.merge_list(
                            Geary.RFC822.Utils.create_cc_addresses_for_reply_all(
                                candidate, sender_addresses
                            )
                        );
                        this.referred_ids.add(candidate.id);
                        new_email = false;
                    }
                }
            }
        }
        if (!new_email) {
            if (this.cc == "") {
                this.context_type = REPLY_SENDER;
            } else {
                this.context_type = REPLY_ALL;
            }

            if (!this.to_row.value.addresses.contains_all(to_addresses)) {
                this.to_row.value.set_modified();
            }
            if (!this.cc_row.value.addresses.contains_all(cc_addresses)) {
                this.cc_row.value.set_modified();
            }
            if (this.bcc != "") {
                this.bcc_row.value.set_modified();
            }

            // We're in compact inline mode, but there are modified email
            // addresses, so set us to use plain inline mode instead so
            // the modified addresses can be seen. If there are CC
            if (this.current_mode == INLINE_COMPACT && (
                    this.to_row.value.is_modified ||
                    this.cc_row.value.is_modified ||
                    this.bcc_row.value.is_modified ||
                    this.reply_to_row.value.is_modified)) {
                set_mode(INLINE);
            }

            // If there's a modified header that would normally be hidden,
            // show full fields.
            if (this.bcc_row.value.is_modified ||
                this.reply_to_row.value.is_modified) {
                this.actions.change_action_state(
                    ACTION_SHOW_EXTENDED_HEADERS, true
                );
            }
        }
    }

    public void present() {
        this.container.present();
        set_focus();
    }

    public void set_focus() {
        bool not_inline = (
            this.current_mode != INLINE &&
            this.current_mode != INLINE_COMPACT
        );
        if (not_inline && Geary.String.is_empty(to)) {
            this.to_row.value.grab_focus();
        } else if (not_inline && Geary.String.is_empty(subject)) {
            this.subject_row.value.grab_focus();
        } else {
            // Need to grab the focus after the content has finished
            // loading otherwise the text caret will not be visible.
            if (this.editor.body.is_content_loaded) {
                this.editor.body.grab_focus();
            } else {
                this.editor.body.content_loaded.connect(() => {
                        this.editor.body.grab_focus();
                    });
            }
        }
    }

    private bool update_from_address(Geary.RFC822.MailboxAddresses? referred_addresses) {
        if (referred_addresses != null) {
            var senders = this.sender_context.account.information.sender_mailboxes;
            var referred = referred_addresses.get_all();
            foreach (Geary.RFC822.MailboxAddress address in senders) {
                if (referred.contains(address)) {
                    this.from = new Geary.RFC822.MailboxAddresses.single(address);
                    return true;
                }
            }
        }
        return false;
    }

    private void on_content_loaded() {
        this.update_signature.begin(null);
        if (this.can_delete_quote) {
            this.editor.body.notify["has-selection"].connect(
                () => { this.can_delete_quote = false; }
            );
        }
    }

    private void show_attachment_overlay(bool visible) {
        if (this.is_attachment_overlay_visible == visible)
            return;

        this.is_attachment_overlay_visible = visible;

        // If we just make the widget invisible, it can still intercept drop signals. So we
        // completely remove it instead.
        if (visible) {
            int height = hidden_on_attachment_drag_over.get_allocated_height();
            this.hidden_on_attachment_drag_over.remove(this.hidden_on_attachment_drag_over_child);
            this.visible_on_attachment_drag_over.pack_start(this.visible_on_attachment_drag_over_child, true, true);
            this.visible_on_attachment_drag_over.set_size_request(-1, height);
        } else {
            this.hidden_on_attachment_drag_over.add(this.hidden_on_attachment_drag_over_child);
            this.visible_on_attachment_drag_over.remove(this.visible_on_attachment_drag_over_child);
            this.visible_on_attachment_drag_over.set_size_request(-1, -1);
        }
   }

    [GtkCallback]
    private void on_set_focus_child() {
        var window = get_toplevel() as Gtk.Window;
        if (window != null) {
            Gtk.Widget? last_focused = window.get_focus();
            if (last_focused == this.editor.body ||
                (last_focused is Gtk.Entry && last_focused.is_ancestor(this))) {
                this.focused_input_widget = last_focused;
            }
        }
    }

    [GtkCallback]
    private bool on_drag_motion() {
        show_attachment_overlay(true);
        return false;
    }

    [GtkCallback]
    private void on_drag_leave() {
        show_attachment_overlay(false);
    }

    [GtkCallback]
    private void on_drag_data_received(Gtk.Widget sender, Gdk.DragContext context, int x, int y,
        Gtk.SelectionData selection_data, uint info, uint time_) {

        bool dnd_success = false;
        if (selection_data.get_length() >= 0) {
            dnd_success = true;

            string uri_list = (string) selection_data.get_data();
            string[] uris = uri_list.strip().split("\n");
            foreach (string uri in uris) {
                if (!uri.has_prefix(FILE_URI_PREFIX))
                    continue;

                try {
                    add_attachment_part(File.new_for_uri(uri.strip()));
                    draft_changed();
                } catch (Error err) {
                    attachment_failed(err.message);
                }
            }
        }

        Gtk.drag_finish(context, dnd_success, false, time_);
    }

    [GtkCallback]
    private bool on_drag_drop(Gtk.Widget sender, Gdk.DragContext context, int x, int y, uint time_) {
        if (context.list_targets() == null)
            return false;

        uint length = context.list_targets().length();
        Gdk.Atom? target_type = null;
        for (uint i = 0; i < length; i++) {
            Gdk.Atom target = context.list_targets().nth_data(i);
            if (target.name() == URI_LIST_MIME_TYPE)
                target_type = target;
        }

        if (target_type == null)
            return false;

        Gtk.drag_get_data(sender, context, target_type, time_);
        return true;
    }

    /** Returns a representation of the current message. */
    public async Geary.ComposedEmail to_composed_email(GLib.DateTime? date_override = null,
                                                       bool for_draft = false) {
        Geary.ComposedEmail email = new Geary.ComposedEmail(
            date_override ?? new DateTime.now_local(),
            from
        ).set_to(
            this.to_row.value.addresses
        ).set_cc(
            this.cc_row.value.addresses
        ).set_bcc(
            this.bcc_row.value.addresses
        ).set_reply_to(
            this.reply_to_row.value.addresses
        ).set_subject(
            this.subject
        ).set_in_reply_to(
            this.in_reply_to
        ).set_references(
            this.references
        );

        email.attached_files.add_all(this.attached_files);
        email.inline_files.set_all(this.inline_files);
        email.cid_files.set_all(this.cid_files);

        email.img_src_prefix = Components.WebView.INTERNAL_URL_PREFIX;

        try {
            email.body_text = yield this.editor.body.get_text();
            if (for_draft) {
                // Must save HTML even if in plain text mode since we
                // need it to restore body/sig/reply state
                email.body_html = yield this.editor.body.get_html_for_draft();
            } else if (this.editor.body.is_rich_text) {
                email.body_html = yield this.editor.body.get_html();
            }
        } catch (Error error) {
            debug("Error getting composer message body: %s", error.message);
        }

        // User-Agent
        email.mailer = Environment.get_prgname() + "/" + Application.Client.VERSION;

        return email;
    }

    /** Appends an email or fragment quoted into the composer. */
    public void append_to_email(Geary.Email referred,
                                string? to_quote,
                                ContextType type)
        throws Geary.EngineError {
        if (!referred.fields.is_all_set(REQUIRED_FIELDS)) {
            throw new Geary.EngineError.INCOMPLETE_MESSAGE(
                "Required fields not met: %s", referred.fields.to_string()
            );
        }

        if (!this.referred_ids.contains(referred.id)) {
            add_recipients_and_ids(type, referred);
        }

        // Always use reply styling, since forward styling doesn't
        // work for inline quotes
        this.editor.body.insert_html(
            Util.Email.quote_email_for_reply(referred, to_quote, HTML)
        );
    }

    private void add_recipients_and_ids(ContextType type,
                                        Geary.Email referred) {
        Gee.List<Geary.RFC822.MailboxAddress> sender_addresses =
            this.sender_context.account.information.sender_mailboxes;

        // Add the sender to the To address list if needed
        this.to_row.value.addresses = Geary.RFC822.Utils.merge_addresses(
            this.to_row.value.addresses,
            Geary.RFC822.Utils.create_to_addresses_for_reply(
                referred, sender_addresses
            )
        );
        if (type == REPLY_ALL) {
            // Add other recipients to the Cc address list if needed,
            // but don't include any already in the To list.
            this.cc_row.value.addresses = Geary.RFC822.Utils.remove_addresses(
                Geary.RFC822.Utils.merge_addresses(
                    this.cc_row.value.addresses,
                    Geary.RFC822.Utils.create_cc_addresses_for_reply_all(
                        referred, sender_addresses
                    )
                ),
                this.to_row.value.addresses
            );
        }

        // Include the new message's id in the In-Reply-To header
        if (referred.message_id != null) {
            this.in_reply_to = this.in_reply_to.merge_id(
                referred.message_id
            );
        }

        // Merge the new message's references with this
        this.references = this.references.merge_list(
            Geary.RFC822.Utils.reply_references(referred)
        );

        // Include the email in the composer's list of referred email
        this.referred_ids.add(referred.id);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        // Override the method since key-press-event is run last, and
        // we want this behaviour to take precedence over the default
        // key handling
        return check_send_on_return(event) && base.key_press_event(event);
    }

    /** Updates the composer's top level window and headerbar title. */
    public void update_window_title() {
        string subject = this.subject.strip();
        if (Geary.String.is_empty(subject)) {
            subject = DEFAULT_TITLE;
        }

        if (this.container != null) {
            this.container.top_window.title = subject;
        }
    }

    /* Activate the close action */
    public void activate_close_action() {
        this.actions.activate_action(ACTION_CLOSE, null);
    }

    internal void set_mode(PresentationMode new_mode) {
        this.current_mode = new_mode;
        this.header.set_mode(new_mode);

        switch (new_mode) {
        case PresentationMode.DETACHED:
        case PresentationMode.PANED:
            this.email_headers.set_visible(true);
            this.subject_row.visible = true;
            break;

        case PresentationMode.INLINE:
            this.email_headers.set_visible(true);
            this.subject_row.visible = false;
            break;

        case PresentationMode.INLINE_COMPACT:
            this.email_headers.set_visible(false);
            this.subject_row.visible = false;
            set_compact_header_recipients();
            break;

        case PresentationMode.CLOSED:
        case PresentationMode.NONE:
            // no-op
            break;
        }

        update_from_field();
    }

    internal void embed_header() {
        if (this.header.parent == null) {
            this.header_container.add(this.header);
            this.header.hexpand = true;
        }
    }

    internal void free_header() {
        if (this.header.parent != null) {
            this.header.parent.remove(this.header);
        }
    }

    private async void finish_loading(string body,
                                      string quote,
                                      bool is_body_complete) {
        update_attachments_view();
        update_pending_attachments(this.pending_include, true);

        this.editor.body.load_html(
            body,
            quote,
            this.top_posting,
            is_body_complete
        );

        var current_account = this.sender_context.account;
        this.open_draft_manager.begin(
            this.saved_id,
            (obj, res) => {
                try {
                    this.open_draft_manager.end(res);
                } catch (GLib.Error error) {
                    this.application.report_problem(
                        new Geary.AccountProblemReport(
                            current_account.information, error
                        )
                    );
                }
            }
        );
    }

    private async bool should_send() {
        bool has_subject = !Geary.String.is_empty(subject.strip());
        bool has_attachment = this.attached_files.size > 0;
        bool has_body = true;

        try {
            has_body = !Geary.String.is_empty(
                yield this.editor.body.get_html()
            );
        } catch (Error err) {
            debug("Failed to get message body: %s", err.message);
        }

        string? confirmation = null;
        if (!has_subject && !has_body && !has_attachment) {
            confirmation = _("Send message with an empty subject and body?");
        } else if (!has_subject) {
            confirmation = _("Send message with an empty subject?");
        } else if (!has_body && !has_attachment) {
            confirmation = _("Send message with an empty body?");
        } else if (!has_attachment) {
            var keywords = string.join(
                "|", ATTACHMENT_KEYWORDS, ATTACHMENT_KEYWORDS_LOCALISED
            );
            var contains = yield this.editor.body.contains_attachment_keywords(
                keywords, this.subject
            );
            if (contains != null && contains) {
                confirmation = _("Send message without an attachment?");
            }
        }
        if (confirmation != null) {
            ConfirmationDialog dialog = new ConfirmationDialog(container.top_window,
                confirmation, null, Stock._OK, "suggested-action");
            return (dialog.run() == Gtk.ResponseType.OK);
        }
        return true;
    }

    // Sends the current message.
    private void on_send() {
        this.should_send.begin((obj, res) => {
                if (this.should_send.end(res)) {
                    this.on_send_async.begin();
                }
            });
    }

    // Used internally by on_send()
    private async void on_send_async() {
        set_enabled(false);

        try {
            yield this.editor.body.clean_content();
            yield this.application.send_composed_email(this);
            yield close_draft_manager(DISCARD);

            if (this.container != null) {
                this.container.close();
            }
        } catch (GLib.Error error) {
            this.application.report_problem(
                new Geary.AccountProblemReport(
                    this.sender_context.account.information, error
                )
            );
        }
    }

    /**
     * Creates and opens the composer's draft manager.
     *
     * Note that since the draft manager may block until a remote
     * connection is open, this method may likewise do so. Hence this
     * method typically needs to be called from the main loop as a
     * background async task using the `begin` async call form.
     */
    private async void open_draft_manager(Geary.EmailIdentifier? editing_draft_id)
        throws GLib.Error {
        if (!this.sender_context.account.information.save_drafts) {
            this.header.show_save_and_close = false;
            return;
        }

        // Cancel any existing opening first
        if (this.draft_manager_opening != null) {
            this.draft_manager_opening.cancel();
        }

        GLib.Cancellable internal_cancellable = new GLib.Cancellable();
        this.sender_context.cancellable.cancelled.connect(
            () => { internal_cancellable.cancel(); }
        );
        this.draft_manager_opening = internal_cancellable;

        Geary.Folder? target = this.save_to;
        if (target == null) {
            target = yield this.sender_context.account.get_required_special_folder_async(
                DRAFTS, internal_cancellable
            );
        }

        Geary.EmailFlags? flags = (
            target.used_as == DRAFTS
            ? new Geary.EmailFlags.with(Geary.EmailFlags.DRAFT)
            : new Geary.EmailFlags()
        );

        bool opened = false;
        try {
            var new_manager = yield new Geary.App.DraftManager(
                this.sender_context.account,
                target,
                flags,
                editing_draft_id,
                internal_cancellable
            );
            new_manager.notify[Geary.App.DraftManager.PROP_DRAFT_STATE]
                .connect(on_draft_state_changed);
            new_manager.notify[Geary.App.DraftManager.PROP_CURRENT_DRAFT_ID]
                .connect(on_draft_id_changed);
            new_manager.fatal
                .connect(on_draft_manager_fatal);
            this.draft_manager = new_manager;
            opened = true;
            debug("Draft manager opened");
        } catch (Geary.EngineError.UNSUPPORTED err) {
            debug(
                "Drafts folder unsupported, no drafts will be saved: %s",
                err.message
            );
        } catch (GLib.Error err) {
            this.header.show_save_and_close = false;
            throw err;
        } finally {
            this.draft_manager_opening = null;
        }

        this.header.show_save_and_close = opened;
        if (opened) {
            update_draft_state();
        }
    }

    /**
     * Closes current draft manager, if any, then opens a new one.
     */
    private async void reopen_draft_manager() {
        // Discard the draft, if any, since it may be on a different
        // account
        var current_account = this.sender_context.account;
        try {
            yield close_draft_manager(DISCARD);
            yield open_draft_manager(null);
            yield save_draft();
        } catch (GLib.Error error) {
            this.application.report_problem(
                new Geary.AccountProblemReport(
                    current_account.information, error
                )
            );
        }
    }

    private async void close_draft_manager(DraftPolicy draft_policy)
        throws GLib.Error {
        var old_manager = this.draft_manager;
        if (old_manager != null) {
            this.draft_timer.reset();

            this.draft_manager = null;
            this.saved_id = null;
            this.draft_status_text = "";

            old_manager.notify[Geary.App.DraftManager.PROP_DRAFT_STATE]
                .disconnect(on_draft_state_changed);
            old_manager.notify[Geary.App.DraftManager.PROP_CURRENT_DRAFT_ID]
                .disconnect(on_draft_id_changed);
            old_manager.fatal.disconnect(on_draft_manager_fatal);

            if (draft_policy == DISCARD) {
                debug("Discarding draft");
                yield old_manager.discard(null);
            }

            yield old_manager.close_async(null);
            debug("Draft manager closed");
        }
    }

    private void update_draft_state() {
        switch (this.draft_manager.draft_state) {
            case Geary.App.DraftManager.DraftState.STORED:
                this.draft_status_text = DRAFT_SAVED_TEXT;
                this.is_draft_saved = true;
            break;

            case Geary.App.DraftManager.DraftState.STORING:
                this.draft_status_text = DRAFT_SAVING_TEXT;
                this.is_draft_saved = true;
            break;

            case Geary.App.DraftManager.DraftState.NOT_STORED:
                this.draft_status_text = "";
                this.is_draft_saved = false;
            break;

            case Geary.App.DraftManager.DraftState.ERROR:
                this.draft_status_text = DRAFT_ERROR_TEXT;
                this.is_draft_saved = false;
            break;

            default:
                assert_not_reached();
        }
    }

    private inline void draft_changed() {
        if (this.should_save) {
            this.draft_timer.start();
        }
        this.draft_status_text = "";
        // can_save depends on the value of this, so reset it after
        // the if test above
        this.is_draft_saved = false;
    }

    // Note that drafts are NOT "linkified."
    private async void save_draft() throws GLib.Error {
        debug("Saving draft");

        // cancel timer in favor of just doing it now
        this.draft_timer.reset();

        if (this.draft_manager != null) {
            Geary.ComposedEmail draft = yield to_composed_email(null, true);
            yield this.draft_manager.update(
                yield new Geary.RFC822.Message.from_composed_email(
                    draft, null, GMime.EncodingConstraint.7BIT, null
                ),
                null,
                null
            );
        }
    }

    private async void save_and_close() {
        set_enabled(false);

        if (this.should_save) {
            try {
                yield save_draft();
            } catch (GLib.Error error) {
                this.application.report_problem(
                    new Geary.AccountProblemReport(
                        this.sender_context.account.information, error
                    )
                );
            }
        }

        // Pass on to the controller so the draft can be re-opened
        // on undo
        if (this.container != null) {
            this.container.close();
        }
        yield this.application.save_composed_email(this);
    }

    private async void discard_and_close() {
        set_enabled(false);

        // Pass on to the controller so the discarded email can be
        // re-opened on undo
        yield this.application.discard_composed_email(this);

        try {
            yield close_draft_manager(DISCARD);
        } catch (GLib.Error error) {
            this.application.report_problem(
                new Geary.AccountProblemReport(
                    this.sender_context.account.information, error
                )
            );
        }

        if (this.container != null) {
            this.container.close();
        }
    }

    private void update_attachments_view() {
        if (this.attached_files.size > 0 )
            attachments_box.show_all();
        else
            attachments_box.hide();
    }

    // Both adds pending attachments and updates the UI if there are
    // any that were left out, that could have been added manually.
    private bool update_pending_attachments(AttachPending include, bool do_add) {
        bool have_added = false;
        bool manual_enabled = false;
        if (this.pending_attachments != null) {
            foreach(Geary.Attachment part in this.pending_attachments) {
                try {
                    string? content_id = part.content_id;
                    Geary.Mime.DispositionType? type =
                        part.content_disposition.disposition_type;
                    File file = part.file;
                    if (type == Geary.Mime.DispositionType.INLINE) {
                        // We only care about the Content Ids of
                        // inline parts, since we need to display them
                        // in the editor web view. However if an
                        // inline part does not have a CID, it is not
                        // possible to be referenced from an IMG SRC
                        // using a cid: URL anyway, so treat it as an
                        // attachment instead.
                        if (content_id != null) {
                            Geary.Memory.FileBuffer file_buffer = new Geary.Memory.FileBuffer(file, true);
                            this.cid_files[content_id] = file_buffer;
                            this.editor.body.add_internal_resource(
                                content_id, file_buffer
                            );
                        } else {
                            type = Geary.Mime.DispositionType.ATTACHMENT;
                        }
                    }

                    if (type == Geary.Mime.DispositionType.INLINE ||
                        include == AttachPending.ALL) {
                        // The pending attachment should be added
                        // automatically, so add it if asked to and it
                        // hasn't already been added
                        if (do_add &&
                            !this.attached_files.contains(file) &&
                            !this.inline_files.has_key(content_id)) {
                            if (type == Geary.Mime.DispositionType.INLINE) {
                                check_attachment_file(file);
                                Geary.Memory.FileBuffer file_buffer = new Geary.Memory.FileBuffer(file, true);
                                string unused;
                                add_inline_part(file_buffer, content_id, out unused);
                            } else {
                                add_attachment_part(file);
                            }
                            have_added = true;
                        }
                    } else {
                        // The pending attachment should only be added
                        // manually
                        manual_enabled = true;
                    }
                } catch (Error err) {
                    attachment_failed(err.message);
                }
            }
        }

        this.editor.new_message_attach_button.visible = !manual_enabled;
        this.editor.conversation_attach_buttons.visible = manual_enabled;

        return have_added;
    }

    private void add_attachment_part(File target)
        throws AttachmentError {
        FileInfo target_info = check_attachment_file(target);

        if (!this.attached_files.add(target)) {
            throw new AttachmentError.DUPLICATE(
                _("“%s” already attached for delivery.").printf(target.get_path())
                );
        }

        Gtk.Box wrapper_box = new Gtk.Box(VERTICAL, 0);
        this.attachments_box.pack_start(wrapper_box);
        wrapper_box.pack_start(new Gtk.Separator(HORIZONTAL));

        Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        wrapper_box.pack_start(box);

        /// In the composer, the filename followed by its filesize, i.e. "notes.txt (1.12KB)"
        string label_text = _("%s (%s)").printf(target.get_basename(),
                                                Files.get_filesize_as_string(target_info.get_size()));
        Gtk.Label label = new Gtk.Label(label_text);
        box.pack_start(label);
        label.halign = Gtk.Align.START;
        label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        label.has_tooltip = true;
        label.query_tooltip.connect(Util.Gtk.query_tooltip_label);

        Gtk.Button remove_button = new Gtk.Button.from_icon_name("user-trash-symbolic", BUTTON);
        box.pack_start(remove_button, false, false);
        remove_button.clicked.connect(() => remove_attachment(target, wrapper_box));

        update_attachments_view();
    }

    private void add_inline_part(Geary.Memory.Buffer target, string content_id, out string unique_contentid)
        throws AttachmentError {

        const string UNIQUE_RENAME_TEMPLATE = "%s_%02u";

        if (target.size == 0)
            throw new AttachmentError.FILE(
                _("“%s” is an empty file.").printf(content_id)
            );

        // Avoid filename conflicts
        unique_contentid = content_id;
        int suffix_index = 0;
        string unsuffixed_filename = "";
        while (this.inline_files.has_key(unique_contentid)) {
            string[] filename_parts = unique_contentid.split(".");

            // Handle no file extension
            int partindex;
            if (filename_parts.length > 1) {
                partindex = filename_parts.length-2;
            } else {
                partindex = 0;
            }
            if (unsuffixed_filename == "")
                unsuffixed_filename = filename_parts[partindex];
            filename_parts[partindex] = UNIQUE_RENAME_TEMPLATE.printf(unsuffixed_filename, suffix_index++);

            unique_contentid = string.joinv(".", filename_parts);
        }

        this.inline_files[unique_contentid] = target;
        this.editor.body.add_internal_resource(
            unique_contentid, target
        );
    }

    private FileInfo check_attachment_file(File target)
        throws AttachmentError {
        FileInfo target_info;
        try {
            target_info = target.query_info("standard::size,standard::type",
                FileQueryInfoFlags.NONE);
        } catch (Error e) {
            throw new AttachmentError.FILE(
                _("“%s” could not be found.").printf(target.get_path())
            );
        }

        if (target_info.get_file_type() == FileType.DIRECTORY) {
            throw new AttachmentError.FILE(
                _("“%s” is a folder.").printf(target.get_path())
            );
        }

        if (target_info.get_size() == 0){
            throw new AttachmentError.FILE(
                _("“%s” is an empty file.").printf(target.get_path())
            );
        }

        try {
            FileInputStream? stream = target.read();
            if (stream != null)
                stream.close();
        } catch(Error e) {
            debug("File '%s' could not be opened for reading. Error: %s", target.get_path(),
                e.message);

            throw new AttachmentError.FILE(
                _("“%s” could not be opened for reading.").printf(target.get_path())
            );
        }

        return target_info;
    }

    private void attachment_failed(string msg) {
        ErrorDialog dialog = new ErrorDialog(this.container.top_window, _("Cannot add attachment"), msg);
        dialog.run();
    }

    private void remove_attachment(File file, Gtk.Box box) {
        if (!this.attached_files.remove(file))
            return;

        foreach (weak Gtk.Widget child in this.attachments_box.get_children()) {
            if (child == box) {
                this.attachments_box.remove(box);
                break;
            }
        }

        update_attachments_view();
        update_pending_attachments(this.pending_include, false);
        draft_changed();
    }

    /**
     * Handle a pasted image, adding it as an inline attachment
     */
    private void paste_image() {
        // The slow operations here are creating the PNG and, to a lesser extent,
        // requesting the image from the clipboard
        this.editor.start_background_work_pulse();

        get_clipboard(Gdk.SELECTION_CLIPBOARD).request_image((clipboard, pixbuf) => {
            if (pixbuf != null) {
                MemoryOutputStream os = new MemoryOutputStream(null);
                pixbuf.save_to_stream_async.begin(os, "png", null, (obj, res) => {
                    try {
                        pixbuf.save_to_stream_async.end(res);
                        os.close();

                        Geary.Memory.ByteBuffer byte_buffer = new Geary.Memory.ByteBuffer.from_memory_output_stream(os);

                        GLib.DateTime time_now = new GLib.DateTime.now();
                        string filename = PASTED_IMAGE_FILENAME_TEMPLATE.printf(time_now.hash());

                        string unique_filename;
                        add_inline_part(byte_buffer, filename, out unique_filename);
                        this.editor.body.insert_image(
                            Components.WebView.INTERNAL_URL_PREFIX + unique_filename
                        );
                    } catch (Error error) {
                        this.application.report_problem(
                            new Geary.ProblemReport(error)
                        );
                    }

                    this.editor.stop_background_work_pulse();
                });
            } else {
                warning("Failed to get image from clipboard");
                this.editor.stop_background_work_pulse();
            }
        });
    }

    /**
     * Handle prompting for an inserting images as inline attachments
     */
    private void insert_image() {
        AttachmentDialog dialog = new AttachmentDialog(
            this.container.top_window, this.config
        );
        Gtk.FileFilter filter = new Gtk.FileFilter();
        // Translators: This is the name of the file chooser filter
        // when inserting an image in the composer.
        filter.set_name(_("Images"));
        filter.add_mime_type("image/*");
        dialog.add_filter(filter);
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            dialog.hide();
            foreach (File file in dialog.get_files()) {
                try {
                    check_attachment_file(file);
                    Geary.Memory.FileBuffer file_buffer = new Geary.Memory.FileBuffer(file, true);
                    string path = file.get_path();
                    string unique_filename;
                    add_inline_part(file_buffer, path, out unique_filename);
                    this.editor.body.insert_image(
                        Components.WebView.INTERNAL_URL_PREFIX + unique_filename
                    );
                } catch (Error err) {
                    attachment_failed(err.message);
                    break;
                }
            }
        }
        dialog.destroy();
    }

    private bool check_send_on_return(Gdk.EventKey event) {
        bool ret = Gdk.EVENT_PROPAGATE;
        switch (Gdk.keyval_name(event.keyval)) {
            case "Return":
            case "KP_Enter":
                // always trap Ctrl+Enter/Ctrl+KeypadEnter to prevent
                // the Enter leaking through to the controls, but only
                // send if send is available
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    this.actions.activate_action(ACTION_SEND, null);
                    ret = Gdk.EVENT_STOP;
                }
            break;
        }
        return ret;
    }

    private void validate_send_button() {
        // To must be valid (and hence non-empty), the other email
        // fields must be either empty or valid.
        get_action(ACTION_SEND).set_enabled(
            this.can_send &&
            this.to_row.value.is_valid &&
            (this.cc_row.value.is_empty || this.cc_row.value.is_valid) &&
            (this.bcc_row.value.is_empty || this.bcc_row.value.is_valid) &&
            (this.reply_to_row.value.is_empty || this.reply_to_row.value.is_valid)
        );

        this.header.show_send = this.can_send;
    }

    private void set_compact_header_recipients() {
        bool tocc = !this.to_row.value.is_empty && !this.cc_row.value.is_empty,
            ccbcc = !(this.to_row.value.is_empty && this.cc_row.value.is_empty) && !this.bcc_row.value.is_empty;
        string label = this.to_row.value.buffer.text + (tocc ? ", " : "")
            + this.cc_row.value.buffer.text + (ccbcc ? ", " : "") + this.bcc_row.value.buffer.text;
        StringBuilder tooltip = new StringBuilder();
        if (this.to_row.value.addresses != null) {
            foreach(Geary.RFC822.MailboxAddress addr in this.to_row.value.addresses) {
                // Translators: Human-readable version of the RFC 822 To header
                tooltip.append("%s %s\n".printf(_("To:"), addr.to_full_display()));
            }
        }
        if (this.cc_row.value.addresses != null) {
            foreach(Geary.RFC822.MailboxAddress addr in this.cc_row.value.addresses) {
                // Translators: Human-readable version of the RFC 822 CC header
                tooltip.append("%s %s\n".printf(_("Cc:"), addr.to_full_display()));
            }
        }
        if (this.bcc_row.value.addresses != null) {
            foreach(Geary.RFC822.MailboxAddress addr in this.bcc_row.value.addresses) {
                // Translators: Human-readable version of the RFC 822 BCC header
                tooltip.append("%s %s\n".printf(_("Bcc:"), addr.to_full_display()));
            }
        }
        if (this.reply_to_row.value.addresses != null) {
            foreach(Geary.RFC822.MailboxAddress addr in this.reply_to_row.value.addresses) {
                // Translators: Human-readable version of the RFC 822 Reply-To header
                tooltip.append("%s%s\n".printf(_("Reply-To: "), addr.to_full_display()));
            }
        }
        this.header.set_recipients(label, tooltip.str.slice(0, -1));  // Remove trailing \n
    }

    private void on_cut(SimpleAction action, Variant? param) {
        var editable = this.container.get_focus() as Gtk.Editable;
        if (editable != null) {
            editable.cut_clipboard();
        }
    }

    private void on_copy(SimpleAction action, Variant? param) {
        var editable = this.container.get_focus() as Gtk.Editable;
        if (editable != null) {
            editable.copy_clipboard();
        }
    }

    private void on_paste(SimpleAction action, Variant? param) {
        var editable = this.container.get_focus() as Gtk.Editable;
        if (editable != null) {
            editable.paste_clipboard();
        }
    }

    private void on_toggle_action(SimpleAction? action, Variant? param) {
        action.change_state(!action.state.get_boolean());
    }

    private void reparent_widget(Gtk.Widget child, Gtk.Container new_parent) {
        ((Gtk.Container) child.get_parent()).remove(child);
        new_parent.add(child);
    }

    private void update_extended_headers(bool reorder=true) {
        bool cc = !this.cc_row.value.is_empty;
        bool bcc = !this.bcc_row.value.is_empty;
        bool reply_to = !this.reply_to_row.value.is_empty;

        if (reorder) {
            if (cc) {
                reparent_widget(this.cc_row, this.filled_headers);
            } else {
                reparent_widget(this.cc_row, this.extended_headers);
            }
            if (bcc) {
                reparent_widget(this.bcc_row, this.filled_headers);
            } else {
                reparent_widget(this.bcc_row, this.extended_headers);
            }
            if (reply_to) {
                reparent_widget(this.reply_to_row, this.filled_headers);
            } else {
                reparent_widget(this.reply_to_row, this.extended_headers);
            }
        }

        this.show_extended_headers.visible = !(cc && bcc && reply_to);
    }

    private void on_show_extended_headers_toggled(GLib.SimpleAction? action,
                                                  GLib.Variant? new_state) {
        bool show_extended = new_state.get_boolean();
        action.set_state(show_extended);

        update_extended_headers();

        this.extended_headers_revealer.reveal_child = show_extended;

        if (show_extended && this.current_mode == INLINE_COMPACT) {
            set_mode(INLINE);
        }
    }

    private bool on_editor_key_press_event(Gdk.EventKey event) {
        // Widget's keypress override doesn't receive non-modifier
        // keys when the editor processes them, regardless if true or
        // false is called; this deals with that issue (specifically
        // so Ctrl+Enter will send the message)
        if (event.is_modifier == 0) {
            if (check_send_on_return(event) == Gdk.EVENT_STOP)
                return Gdk.EVENT_STOP;
        }

        if (this.can_delete_quote) {
            this.can_delete_quote = false;
            if (event.is_modifier == 0 && event.keyval == Gdk.Key.BackSpace) {
                this.editor.body.delete_quoted_message();
                return Gdk.EVENT_STOP;
            }
        }

        return Gdk.EVENT_PROPAGATE;
    }

    private GLib.SimpleAction? get_action(string action_name) {
        return this.actions.lookup_action(action_name) as GLib.SimpleAction;
    }

    private bool add_account_emails_to_from_list(
        Application.AccountContext other_account,
        bool set_active = false
    ) {
        bool is_primary = true;
        Geary.AccountInformation info = other_account.account.information;
        foreach (Geary.RFC822.MailboxAddress mailbox in info.sender_mailboxes) {
            Geary.RFC822.MailboxAddresses addresses =
                new Geary.RFC822.MailboxAddresses.single(mailbox);

            string display = mailbox.to_full_display();
            if (!is_primary) {
                // Displayed in the From dropdown to indicate an
                // "alternate email address" for an account.  The first
                // printf argument will be the alternate email address,
                // and the second will be the account's primary email
                // address.
                display = _("%1$s via %2$s").printf(display, info.display_name);
            }
            is_primary = false;

            this.from_row.value.append_text(display);
            this.from_list.add(new FromAddressMap(other_account, addresses));

            if (!set_active && this.from.equal_to(addresses)) {
                this.from_row.value.set_active(this.from_list.size - 1);
                set_active = true;
            }
        }
        return set_active;
    }

    private void update_info_label() {
        string text = "";
        if (this.can_delete_quote) {
            text = BACKSPACE_TEXT;
        } else {
            text = this.draft_status_text;
        }
        this.editor.set_info_label(text);
    }

    // Updates from combobox contents and visibility, returns true if
    // the from address had to be set
    private bool update_from_field() {
        this.from_row.visible = false;
        this.from_row.value.changed.disconnect(on_from_changed);

        // Don't show in inline unless the current account has
        // multiple email accounts or aliases, since these will be replies to a
        // conversation
        if ((this.current_mode == INLINE ||
             this.current_mode == INLINE_COMPACT) &&
            !this.has_multiple_from_addresses) {
            return false;
        }

        // If there's only one account and it not have any aliases,
        // show nothing.
        Gee.Collection<Application.AccountContext> accounts =
            this.application.get_account_contexts();
        if (accounts.size < 1 ||
            (accounts.size == 1 &&
            !Geary.Collection.first(
                accounts
            ).account.information.has_sender_aliases)) {
            return false;
        }

        this.from_row.visible = true;
        this.from_row.value.remove_all();
        this.from_list = new Gee.ArrayList<FromAddressMap>();

        // Always add at least the current account. The var set_active
        // is set to true if the current message's from address has
        // been set in the ComboBox.
        bool set_active = add_account_emails_to_from_list(this.sender_context);
        foreach (var account in accounts) {
            if (account != this.sender_context) {
                set_active = add_account_emails_to_from_list(
                    account, set_active
                );
            }
        }

        if (!set_active) {
            // The identity or account that was active before has been
            // removed use the best we can get now (primary address of
            // the account or any other)
            this.from_row.value.set_active(0);
        }

        this.from_row.value.changed.connect(on_from_changed);
        return !set_active;
    }

    private void update_from() throws Error {
        int index = this.from_row.value.get_active();
        if (index >= 0) {
            FromAddressMap selected = this.from_list.get(index);
            this.from = selected.from;

            if (selected.account != this.sender_context) {
                this.sender_context = selected.account;
                this.update_signature.begin(null);
                load_entry_completions();

                this.reopen_draft_manager.begin();
            }
        }
    }

    private async void update_signature(Cancellable? cancellable = null) {
        string sig = "";
        Geary.AccountInformation account =
            this.sender_context.account.information;
        if (account.use_signature) {
            sig = account.signature;
            if (Geary.String.is_empty_or_whitespace(sig)) {
                // No signature is specified in the settings, so use
                // ~/.signature
                File signature_file = File.new_for_path(Environment.get_home_dir()).get_child(".signature");
                try {
                    uint8[] data;
                    yield signature_file.load_contents_async(cancellable, out data, null);
                    sig = (string) data;
                } catch (Error error) {
                    if (!(error is IOError.NOT_FOUND)) {
                        debug("Error reading signature file %s: %s", signature_file.get_path(), error.message);
                    }
                }
            }
        }

        // Still want to update the signature even if it is empty,
        // since when changing the selected from account, if the
        // previously selected account had a sig but the newly
        // selected account does not, the old sig gets cleared out.
        if (Geary.String.is_empty_or_whitespace(sig)) {
            // Clear out multiple spaces etc so smart_escape
            // doesn't create &nbsp;'s
            sig = "";
        }
        this.editor.body.update_signature(Geary.HTML.smart_escape(sig));
    }

    private void update_subject_spell_checker() {
        Gspell.Language? lang = null;
        string[] langs = this.config.get_spell_check_languages();
        if (langs.length == 1) {
            lang = Gspell.Language.lookup(langs[0]);
        } else {
            // Since GSpell doesn't support multiple languages (see
            // <https://gitlab.gnome.org/GNOME/gspell/issues/5>) and
            // we don't support spell checker language priority, use
            // the first matching most preferred language, if any.
            foreach (string pref in Util.I18n.get_user_preferred_languages()) {
                if (pref in langs) {
                    lang = Gspell.Language.lookup(pref);
                    if (lang != null) {
                        break;
                    }
                }
            }

            if (lang == null) {
                // No preferred lang found, so just use first
                // supported matching language
                foreach (string pref in langs) {
                    lang = Gspell.Language.lookup(pref);
                    if (lang != null) {
                        break;
                    }
                }
            }
        }

        var buffer = Gspell.EntryBuffer.get_from_gtk_entry_buffer(
            this.subject_row.value.buffer
        );
        Gspell.Checker checker = null;
        if (lang != null) {
            checker = this.subject_spell_checker;
            checker.language = lang;
        }
        this.subject_spell_entry.inline_spell_checking = (checker != null);
        buffer.spell_checker = checker;
    }

    private void on_draft_id_changed() {
        this.saved_id = this.draft_manager.current_draft_id;
    }

    private void on_draft_manager_fatal(Error err) {
        this.draft_status_text = DRAFT_ERROR_TEXT;
    }

    private void on_draft_state_changed() {
        update_draft_state();
    }

    private void on_subject_changed() {
        draft_changed();
        update_window_title();
    }

    private void on_envelope_changed() {
        draft_changed();
        update_extended_headers(false);
        validate_send_button();
    }

    private void on_from_changed() {
        try {
            update_from();
        } catch (Error err) {
            debug("Error updating from address: %s", err.message);
        }
    }

    private void on_expand_compact_headers() {
        set_mode(INLINE);
    }

    private void on_detach() {
        detach(this.container.top_window.application as Application.Client);
    }

    private void on_add_attachment() {
        AttachmentDialog dialog = new AttachmentDialog(
            this.container.top_window, this.config
        );
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            dialog.hide();
            foreach (File file in dialog.get_files()) {
                try {
                    add_attachment_part(file);
                    draft_changed();
                } catch (Error err) {
                    attachment_failed(err.message);
                    break;
                }
            }

        }
        dialog.destroy();
    }

    private void on_pending_attachments() {
        if (update_pending_attachments(AttachPending.ALL, true)) {
            draft_changed();
        }
    }

    private void on_close() {
        conditional_close(this.container is Window);
    }

    private void on_show_window_menu() {
        Application.MainWindow main = null;
        if (this.container != null) {
            main = this.container.top_window as Application.MainWindow;
        }
        if (main != null) {
            main.show_window_menu();
        }
    }

    private void on_show_help_overlay() {
        var overlay = this.container.top_window.get_help_overlay();
        overlay.section_name = "composer";
        overlay.show();
    }

    private void on_discard() {
        if (this.container is Window) {
            conditional_close(true);
        } else {
            this.discard_and_close.begin();
        }
    }

    private void on_draft_timeout() {
        var current_account = this.sender_context.account;
        this.save_draft.begin(
            (obj, res) => {
                try {
                    this.save_draft.end(res);
                } catch (GLib.Error error) {
                    this.application.report_problem(
                        new Geary.AccountProblemReport(
                            current_account.information, error
                        )
                    );
                }
            }
        );
    }

    private void on_account_available() {
        update_from_field();
    }

    private void on_account_unavailable() {
        if (update_from_field()) {
            on_from_changed();
        }
    }

    /**
     * Handle a dropped image file, adding it as an inline attachment
     */
    private void on_image_file_dropped(string filename, string file_type, uint8[] contents) {
        Geary.Memory.ByteBuffer buffer = new Geary.Memory.ByteBuffer(contents, contents.length);
        string unique_filename;
        try {
            add_inline_part(buffer, filename, out unique_filename);
        } catch (AttachmentError err) {
            warning("Couldn't attach dropped empty file %s", filename);
            return;
        }

        this.editor.body.insert_image(
            Components.WebView.INTERNAL_URL_PREFIX + unique_filename
        );
    }

}
