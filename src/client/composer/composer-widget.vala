/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private errordomain AttachmentError {
    FILE,
    DUPLICATE
}

// The actual widget for sending messages. Should be put in a ComposerContainer
[GtkTemplate (ui = "/org/gnome/Geary/composer-widget.ui")]
public class ComposerWidget : Gtk.EventBox {
    public enum ComposeType {
        NEW_MESSAGE,
        REPLY,
        REPLY_ALL,
        FORWARD
    }
    
    public enum CloseStatus {
        DO_CLOSE,
        PENDING_CLOSE,
        CANCEL_CLOSE
    }
    
    public enum ComposerState {
        DETACHED,
        PANED,
        NEW,
        INLINE,
        INLINE_COMPACT
    }

    private enum AttachPending { ALL, INLINE_ONLY }

    private class FromAddressMap {
        public Geary.Account account;
        public Geary.RFC822.MailboxAddresses from;
        public FromAddressMap(Geary.Account a, Geary.RFC822.MailboxAddresses f) {
            account = a;
            from = f;
        }
    }

    private SimpleActionGroup actions = new SimpleActionGroup();

    private const string ACTION_UNDO = "undo";
    private const string ACTION_REDO = "redo";
    private const string ACTION_CUT = "cut";
    private const string ACTION_COPY = "copy";
    private const string ACTION_COPY_LINK = "copy-link";
    private const string ACTION_PASTE = "paste";
    private const string ACTION_PASTE_WITH_FORMATTING = "paste-with-formatting";
    private const string ACTION_SELECT_ALL = "select-all";
    private const string ACTION_BOLD = "bold";
    private const string ACTION_ITALIC = "italic";
    private const string ACTION_UNDERLINE = "underline";
    private const string ACTION_STRIKETHROUGH = "strikethrough";
    private const string ACTION_FONT_SIZE = "font-size";
    private const string ACTION_FONT_FAMILY = "font-family";
    private const string ACTION_REMOVE_FORMAT = "remove-format";
    private const string ACTION_INDENT = "indent";
    private const string ACTION_OUTDENT = "outdent";
    private const string ACTION_JUSTIFY = "justify";
    private const string ACTION_COLOR = "color";
    private const string ACTION_INSERT_IMAGE = "insert-image";
    private const string ACTION_INSERT_LINK = "insert-link";
    private const string ACTION_COMPOSE_AS_HTML = "compose-as-html";
    private const string ACTION_SHOW_EXTENDED = "show-extended";
    private const string ACTION_CLOSE = "close";
    private const string ACTION_CLOSE_AND_SAVE = "close-and-save";
    private const string ACTION_CLOSE_AND_DISCARD = "close-and-discard";
    private const string ACTION_DETACH = "detach";
    private const string ACTION_SEND = "send";
    private const string ACTION_ADD_ATTACHMENT = "add-attachment";
    private const string ACTION_ADD_ORIGINAL_ATTACHMENTS = "add-original-attachments";
    private const string ACTION_SELECT_DICTIONARY = "select-dictionary";

    private const string[] html_actions = {
        ACTION_BOLD, ACTION_ITALIC, ACTION_UNDERLINE, ACTION_STRIKETHROUGH, ACTION_FONT_SIZE,
        ACTION_FONT_FAMILY, ACTION_REMOVE_FORMAT, ACTION_COLOR, ACTION_JUSTIFY,
        ACTION_INSERT_IMAGE, ACTION_INSERT_LINK, ACTION_COPY_LINK, ACTION_PASTE_WITH_FORMATTING
    };

    private const ActionEntry[] action_entries = {
        // Editor commands
        {ACTION_UNDO,                     on_action                                     },
        {ACTION_REDO,                     on_action                                     },
        {ACTION_CUT,                      on_cut                                        },
        {ACTION_COPY,                     on_copy                                       },
        {ACTION_COPY_LINK,                on_copy_link                                  },
        {ACTION_PASTE,                    on_paste                                      },
        {ACTION_PASTE_WITH_FORMATTING,    on_paste_with_formatting                      },
        {ACTION_SELECT_ALL,               on_select_all                                 },
        {ACTION_BOLD,                     on_action,                null,      "false"  },
        {ACTION_ITALIC,                   on_action,                null,      "false"  },
        {ACTION_UNDERLINE,                on_action,                null,      "false"  },
        {ACTION_STRIKETHROUGH,            on_action,                null,      "false"  },
        {ACTION_FONT_SIZE,                on_font_size,              "s",   "'medium'"  },
        {ACTION_FONT_FAMILY,              on_font_family,            "s",     "'sans'"  },
        {ACTION_REMOVE_FORMAT,            on_remove_format,         null,      "false"  },
        {ACTION_INDENT,                   on_indent                                     },
        {ACTION_OUTDENT,                  on_action                                     },
        {ACTION_JUSTIFY,                  on_justify,                "s",     "'left'"  },
        {ACTION_COLOR,                    on_select_color                               },
        {ACTION_INSERT_IMAGE,             on_insert_image                               },
        {ACTION_INSERT_LINK,              on_insert_link                                },
        // Composer commands
        {ACTION_COMPOSE_AS_HTML,          on_toggle_action,        null,   "true",  on_compose_as_html_toggled },
        {ACTION_SHOW_EXTENDED,            on_toggle_action,        null,  "false",  on_show_extended_toggled   },
        {ACTION_CLOSE,                    on_close                                                             },
        {ACTION_CLOSE_AND_SAVE,           on_close_and_save                                                    },
        {ACTION_CLOSE_AND_DISCARD,        on_close_and_discard                                                 },
        {ACTION_DETACH,                   on_detach                                                            },
        {ACTION_SEND,                     on_send                                                              },
        {ACTION_ADD_ATTACHMENT,           on_add_attachment                                                    },
        {ACTION_ADD_ORIGINAL_ATTACHMENTS, on_pending_attachments                                               },
        {ACTION_SELECT_DICTIONARY,        on_select_dictionary                                                 },
    };

    public static Gee.MultiMap<string, string> action_accelerators = new Gee.HashMultiMap<string, string>();
    static construct {
        action_accelerators.set(ACTION_UNDO, "<Ctrl>z");
        action_accelerators.set(ACTION_REDO, "<Ctrl><Shift>z");
        action_accelerators.set(ACTION_CUT, "<Ctrl>x");
        action_accelerators.set(ACTION_COPY, "<Ctrl>x");
        action_accelerators.set(ACTION_PASTE, "<Ctrl>v");
        action_accelerators.set(ACTION_PASTE_WITH_FORMATTING, "<Ctrl><Shift>v");
        action_accelerators.set(ACTION_INSERT_IMAGE, "<Ctrl>g");
        action_accelerators.set(ACTION_INSERT_LINK, "<Ctrl>l");
        action_accelerators.set(ACTION_INDENT, "<Ctrl>bracketright");
        action_accelerators.set(ACTION_OUTDENT, "<Ctrl>bracketleft");
        action_accelerators.set(ACTION_REMOVE_FORMAT, "<Ctrl>space");
        action_accelerators.set(ACTION_BOLD, "<Ctrl>b");
        action_accelerators.set(ACTION_ITALIC, "<Ctrl>i");
        action_accelerators.set(ACTION_UNDERLINE, "<Ctrl>u");
        action_accelerators.set(ACTION_STRIKETHROUGH, "<Ctrl>k");
        action_accelerators.set(ACTION_CLOSE, "<Ctrl>w");
        action_accelerators.set(ACTION_CLOSE, "Escape");
        action_accelerators.set(ACTION_ADD_ATTACHMENT, "<Ctrl>t");
        action_accelerators.set(ACTION_DETACH, "<Ctrl>d");
    }

    private const string DRAFT_SAVED_TEXT = _("Saved");
    private const string DRAFT_SAVING_TEXT = _("Saving");
    private const string DRAFT_ERROR_TEXT = _("Error saving");
    private const string BACKSPACE_TEXT = _("Press Backspace to delete quote");
    private const string DEFAULT_TITLE = _("New Message");

    private const string URI_LIST_MIME_TYPE = "text/uri-list";
    private const string FILE_URI_PREFIX = "file://";
    private const string HTML_BODY = """
        <html><head><title></title>
        <style>
        body {
            margin: 0px !important;
            padding: 0 !important;
            background-color: white !important;
            font-size: medium !important;
        }
        body.plain, body.plain * {
            font-family: monospace !important;
            font-weight: normal;
            font-style: normal;
            font-size: medium !important;
            color: black;
            text-decoration: none;
        }
        body.plain a {
            cursor: text;
        }
        #message-body {
            box-sizing: border-box;
            padding: 10px;
            outline: 0px solid transparent;
            min-height: 100%;
        }
        blockquote {
            margin-top: 0px;
            margin-bottom: 0px;
            margin-left: 10px;
            margin-right: 10px;
            padding-left: 5px;
            padding-right: 5px;
            background-color: white;
            border: 0;
            border-left: 3px #aaa solid;
        }
        pre {
            white-space: pre-wrap;
            margin: 0;
        }
        </style>
        </head><body>
        <div id="message-body" contenteditable="true" dir="auto"></div>
        </body></html>""";
    private const string CURSOR = "<span id=\"cursormarker\"></span>";
    
    private const int DRAFT_TIMEOUT_SEC = 10;
    
    public const string ATTACHMENT_KEYWORDS_SUFFIX = ".doc|.pdf|.xls|.ppt|.rtf|.pps";
    
    // A list of keywords, separated by pipe ("|") characters, that suggest an attachment; since
    // this is full-word checking, include all variants of each word.  No spaces are allowed.
    public const string ATTACHMENT_KEYWORDS_LOCALIZED = _("attach|attaching|attaches|attachment|attachments|attached|enclose|enclosed|enclosing|encloses|enclosure|enclosures");
    
    private delegate bool CompareStringFunc(string key, string token);
    
    public Geary.Account account { get; private set; }

    public Geary.RFC822.MailboxAddresses from { get; private set; }

    public string to {
        get { return this.to_entry.get_text(); }
        set { this.to_entry.set_text(value); }
    }

    public string cc {
        get { return this.cc_entry.get_text(); }
        set { this.cc_entry.set_text(value); }
    }

    public string bcc {
        get { return this.bcc_entry.get_text(); }
        set { this.bcc_entry.set_text(value); }
    }

    public string reply_to {
        get { return this.reply_to_entry.get_text(); }
        set { this.reply_to_entry.set_text(value); }
    }

    public Gee.Set<Geary.RFC822.MessageID> in_reply_to = new Gee.HashSet<Geary.RFC822.MessageID>();
    public string references { get; set; }

    public string subject {
        get { return this.subject_entry.get_text(); }
        set { this.subject_entry.set_text(value); }
    }

    public string message {
        owned get { return get_html(); }
        set {
            this.body_html = value;
            this.editor.load_html(HTML_BODY, null);
        }
    }

    public ComposerState state { get; internal set; }

    public ComposeType compose_type { get; private set; default = ComposeType.NEW_MESSAGE; }

    public Gee.Set<Geary.EmailIdentifier> referred_ids = new Gee.HashSet<Geary.EmailIdentifier>();

    public bool blank {
        get {
            return this.to_entry.empty &&
                this.cc_entry.empty &&
                this.bcc_entry.empty &&
                this.reply_to_entry.empty &&
                this.subject_entry.buffer.length == 0 &&
                !this.editor.can_undo() &&
                this.attached_files.size == 0;
        }
    }

    public ComposerHeaderbar header { get; private set; }

    public ComposerWebView editor { get; private set; default = new ComposerWebView(); }

    public string draft_save_text { get; private set; }

    public bool can_delete_quote { get; private set; default = false; }

    public string toolbar_text { get; set; }

    public string window_title { get; set; }

    public Configuration config { get; set; }

    [GtkChild]
    internal Gtk.ScrolledWindow editor_scrolled;

    private ContactListStore? contact_list_store = null;

    private string? body_html = null;

    [GtkChild]
    private Gtk.Box composer_container;
    [GtkChild]
    private Gtk.Label from_label;
    [GtkChild]
    private Gtk.Label from_single;
    [GtkChild]
    private Gtk.ComboBoxText from_multiple;
    private Gee.ArrayList<FromAddressMap> from_list = new Gee.ArrayList<FromAddressMap>();
    [GtkChild]
    private Gtk.EventBox to_box;
    [GtkChild]
    private Gtk.Label to_label;
    private EmailEntry to_entry;
    [GtkChild]
    private Gtk.EventBox cc_box;
    [GtkChild]
    private Gtk.Label cc_label;
    private EmailEntry cc_entry;
    [GtkChild]
    private Gtk.EventBox bcc_box;
    [GtkChild]
    private Gtk.Label bcc_label;
    private EmailEntry bcc_entry;
    [GtkChild]
    private Gtk.EventBox reply_to_box;
    [GtkChild]
    private Gtk.Label reply_to_label;
    private EmailEntry reply_to_entry;
    [GtkChild]
    private Gtk.Label subject_label;
    [GtkChild]
    private Gtk.Entry subject_entry;
    [GtkChild]
    private Gtk.Label message_overlay_label;
    [GtkChild]
    private Gtk.Box attachments_box;
    [GtkChild]
    private Gtk.Box hidden_on_attachment_drag_over;
    [GtkChild]
    private Gtk.Box visible_on_attachment_drag_over;
    [GtkChild]
    private Gtk.Widget hidden_on_attachment_drag_over_child;
    [GtkChild]
    private Gtk.Widget visible_on_attachment_drag_over_child;
    [GtkChild]
    private Gtk.Widget recipients;
    [GtkChild]
    private Gtk.Box header_area;
    [GtkChild]
    private Gtk.Box composer_toolbar;
    [GtkChild]
    private Gtk.Button remove_format_button;
    [GtkChild]
    private Gtk.Button select_dictionary_button;
    [GtkChild]
    private Gtk.MenuButton menu_button;
    [GtkChild]
    private Gtk.Label info_label;
    [GtkChild]
    private Gtk.Box message_area;

    private Menu html_menu;
    private Menu plain_menu;
    private Menu context_menu_model;

    private SpellCheckPopover? spell_check_popover = null;
    private string? hover_url = null;
    private bool is_attachment_overlay_visible = false;
    private Geary.RFC822.MailboxAddresses reply_to_addresses;
    private Geary.RFC822.MailboxAddresses reply_cc_addresses;
    private string reply_subject = "";
    private string forward_subject = "";
    private bool top_posting = true;
    private string? last_quote = null;

    private Gee.List<Geary.Attachment>? pending_attachments = null;
    private AttachPending pending_include = AttachPending.INLINE_ONLY;
    private Gee.Set<File> attached_files = new Gee.HashSet<File>(Geary.Files.nullable_hash,
        Geary.Files.nullable_equal);
    private Gee.Set<File> inline_files = new Gee.HashSet<File>(Geary.Files.nullable_hash,
        Geary.Files.nullable_equal);
    private Gee.Map<string,File> cid_files = new Gee.HashMap<string,File>();

    private Geary.App.DraftManager? draft_manager = null;
    private Geary.EmailFlags draft_flags = new Geary.EmailFlags.with(Geary.EmailFlags.DRAFT);
    private uint draft_save_timeout_id = 0;
    private bool is_closing = false;

    private ComposerContainer container {
        get { return (ComposerContainer) parent; }
    }


    public signal void draft_id_changed(Geary.EmailIdentifier? id);


    public ComposerWidget(Geary.Account account, ComposeType compose_type, Configuration config,
        Geary.Email? referred = null, string? quote = null, bool is_referred_draft = false) {
        this.config = config;
        this.header = new ComposerHeaderbar(config);
        this.account = account;
        this.compose_type = compose_type;
        if (this.compose_type == ComposeType.NEW_MESSAGE)
            this.state = ComposerState.NEW;
        else if (this.compose_type == ComposeType.FORWARD)
            this.state = ComposerState.INLINE;
        else
            this.state = ComposerState.INLINE_COMPACT;

        // Setup drag 'n drop
        const Gtk.TargetEntry[] target_entries = { { URI_LIST_MIME_TYPE, 0, 0 } };
        Gtk.drag_dest_set(this, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            target_entries, Gdk.DragAction.COPY);

        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK);

        this.visible_on_attachment_drag_over.remove(this.visible_on_attachment_drag_over_child);
        bind_property("state", recipients, "visible", BindingFlags.SYNC_CREATE,
            (binding, source_value, ref target_value) => {
                target_value = (this.state != ComposerState.INLINE_COMPACT);
                return true;
            });
        BindingTransformFunc bind_not_inline = (binding, source_value, ref target_value) => {
            target_value = (this.state != ComposerState.INLINE && state != ComposerState.PANED);
            return true;
        };
        bind_property("state", this.subject_label, "visible", BindingFlags.SYNC_CREATE, bind_not_inline);
        bind_property("state", this.subject_entry, "visible", BindingFlags.SYNC_CREATE, bind_not_inline);
        notify["state"].connect((s, p) => { update_from_field(); });

        BindingTransformFunc set_toolbar_text = (binding, source_value, ref target_value) => {
                if (draft_save_text == "" && can_delete_quote)
                    target_value = BACKSPACE_TEXT;
                else
                    target_value = draft_save_text;
                return true;
            };
        bind_property("draft-save-text", this, "toolbar-text", BindingFlags.SYNC_CREATE,
            set_toolbar_text);
        bind_property("can-delete-quote", this, "toolbar-text", BindingFlags.SYNC_CREATE,
            set_toolbar_text);
        this.to_entry = new EmailEntry(this);
        this.to_box.add(to_entry);
        this.cc_entry = new EmailEntry(this);
        this.cc_box.add(cc_entry);
        this.bcc_entry = new EmailEntry(this);
        this.bcc_box.add(bcc_entry);
        this.reply_to_entry = new EmailEntry(this);
        this.reply_to_box.add(reply_to_entry);

        this.to_label.set_mnemonic_widget(this.to_entry);
        this.cc_label.set_mnemonic_widget(this.cc_entry);
        this.bcc_label.set_mnemonic_widget(this.bcc_entry);
        this.reply_to_label.set_mnemonic_widget(this.reply_to_entry);

        this.to_entry.margin_top = this.cc_entry.margin_top = this.bcc_entry.margin_top = this.reply_to_entry.margin_top = 6;

        // Initialize menus
        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/composer-menus.ui"
        );
        this.html_menu = (Menu) builder.get_object("html_menu_model");
        this.plain_menu = (Menu) builder.get_object("plain_menu_model");
        this.context_menu_model = (Menu) builder.get_object("context_menu_model");

        this.subject_entry.bind_property("text", this, "window-title", BindingFlags.SYNC_CREATE,
            (binding, source_value, ref target_value) => {
                target_value = Geary.String.is_empty_or_whitespace(this.subject_entry.text)
                    ? DEFAULT_TITLE : this.subject_entry.text.strip();
                return true;
            });

        embed_header();
        bind_property("state", this.header, "state", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);

        // Listen to account signals to update from menu.
        Geary.Engine.instance.account_available.connect(() => {
                update_from_field();
            });
        Geary.Engine.instance.account_unavailable.connect(() => {
                if (update_from_field()) {
                    on_from_changed();
                }
            });
        // TODO: also listen for account updates to allow adding identities while writing an email

        bind_property("toolbar-text", this.info_label, "label", BindingFlags.SYNC_CREATE);

        this.from = new Geary.RFC822.MailboxAddresses.single(account.information.primary_mailbox);

        if (referred != null) {
            fill_in_from_referred(referred, quote);

            if (is_referred_draft ||
                compose_type == ComposeType.NEW_MESSAGE ||
                compose_type == ComposeType.FORWARD) {
                this.pending_include = AttachPending.ALL;
            }
        }

        update_from_field();
        update_pending_attachments(this.pending_include, true);

        // only add signature if the option is actually set and if this is not a draft
        if (this.account.information.use_email_signature && !is_referred_draft)
            add_signature_and_cursor();
        else
            set_cursor();

        // Add actions once every element has been initialized and added
        initialize_actions();

        // Connect everything (can only happen after actions were added)
        validate_send_button();
        set_header_recipients();
        this.to_entry.changed.connect(validate_send_button);
        this.cc_entry.changed.connect(validate_send_button);
        this.bcc_entry.changed.connect(validate_send_button);
        this.reply_to_entry.changed.connect(validate_send_button);
        this.editor.context_menu.connect(on_context_menu);
        this.editor.link_activated.connect(on_link_activated);
        this.editor.load_changed.connect(on_load_changed);
        this.editor.mouse_target_changed.connect(on_mouse_target_changed);
        this.editor.text_attributes_changed.connect(on_text_attributes_changed);
        // this.editor.move_focus.connect(update_actions);
        // this.editor.copy_clipboard.connect(update_actions);
        // this.editor.cut_clipboard.connect(update_actions);
        // this.editor.paste_clipboard.connect(update_actions);
        // this.editor.undo.connect(update_actions);
        // this.editor.redo.connect(update_actions);
        // this.editor.selection_changed.connect(update_actions);
        this.editor.key_press_event.connect(on_editor_key_press);
        //this.editor.user_changed_contents.connect(reset_draft_timer);

        // only do this after setting body_html
        this.editor.load_html(HTML_BODY, null);

        GearyApplication.instance.config.settings.changed[Configuration.SPELL_CHECK_KEY].connect(
            on_spell_check_changed);

        // WebKit.Settings s = this.editor.settings;
        // s.enable_spell_checking = GearyApplication.instance.config.spell_check;
        // s.spell_checking_languages = string.joinv(
        //     ",", GearyApplication.instance.config.spell_check_languages
        // );
        // this.editor.settings = s;

        this.editor_scrolled.add(editor);

        // Place the message area before the compose toolbar in the focus chain, so that
        // the user can tab directly from the Subject: field to the message area.
        // TODO: after bumping the min. GTK+ version to 3.16, we can/should do this in the UI file.
        List<Gtk.Widget> chain = new List<Gtk.Widget>();
        chain.append(this.hidden_on_attachment_drag_over);
        chain.append(this.message_area);
        chain.append(this.composer_toolbar);
        chain.append(this.attachments_box);
        this.composer_container.set_focus_chain(chain);

        // Don't do this in an overridden version of the destroy
        // method, it somehow ends up in an infinite loop
        destroy.connect(() => { close_draft_manager_async.begin(null); });
    }

    public ComposerWidget.from_mailto(Geary.Account account, string mailto, Configuration config) {
        this(account, ComposeType.NEW_MESSAGE, config);
        
        Gee.HashMultiMap<string, string> headers = new Gee.HashMultiMap<string, string>();
        if (mailto.length > Geary.ComposedEmail.MAILTO_SCHEME.length) {
            // Parse the mailto link.
            string[] parts = mailto.substring(Geary.ComposedEmail.MAILTO_SCHEME.length).split("?", 2);
            string email = Uri.unescape_string(parts[0]);
            string[] params = parts.length == 2 ? parts[1].split("&") : new string[0];
            foreach (string param in params) {
                string[] param_parts = param.split("=", 2);
                if (param_parts.length == 2) {
                    headers.set(Uri.unescape_string(param_parts[0]).down(),
                        Uri.unescape_string(param_parts[1]));
                }
            }

            // Assemble the headers.
            if (email.length > 0 && headers.contains("to"))
                this.to = "%s,%s".printf(email, Geary.Collection.get_first(headers.get("to")));
            else if (email.length > 0)
                this.to = email;
            else if (headers.contains("to"))
                this.to = Geary.Collection.get_first(headers.get("to"));

            if (headers.contains("cc"))
                this.cc = Geary.Collection.get_first(headers.get("cc"));

            if (headers.contains("bcc"))
                this.bcc = Geary.Collection.get_first(headers.get("bcc"));

            if (headers.contains("subject"))
                this.subject = Geary.Collection.get_first(headers.get("subject"));

            if (headers.contains("body"))
                this.body_html = Geary.HTML.preserve_whitespace(Geary.HTML.escape_markup(
                    Geary.Collection.get_first(headers.get("body"))));

            Gee.List<string> attachments = new Gee.LinkedList<string>();
            attachments.add_all(headers.get("attach"));
            attachments.add_all(headers.get("attachment"));
            foreach (string attachment in attachments) {
                try {
                    add_attachment(File.new_for_commandline_arg(attachment));
                } catch (Error err) {
                    attachment_failed(err.message);
                }
            }
        }
    }

    // Initializes all actions and adds them to the action group
    private void initialize_actions() {
        this.actions.add_action_entries(action_entries, this);

        // for some reason, we can't use the same prefix.
        insert_action_group("cmp", this.actions);
        this.header.insert_action_group("cmh", this.actions);

        update_actions();
    }

    /**
     * Loads and sets contact auto-complete data for the current account.
     */
    public async void load_entry_completions() {
        // XXX Since ContactListStore hooks into ContactStore to
        // listen for contacts being added and removed,
        // GearyController or some composer-related controller should
        // construct an instance per account and keep it around for
        // the lifetime of the app, since there can be tens of
        // thousands of contacts for large accounts.
        Geary.ContactStore contacts = this.account.get_contact_store();
        if (this.contact_list_store == null ||
            this.contact_list_store.contact_store != contacts) {
            ContactListStore store = new ContactListStore(contacts);
            this.contact_list_store = store;
            yield store.load();

            this.to_entry.completion = new ContactEntryCompletion(store);
            this.cc_entry.completion = new ContactEntryCompletion(store);
            this.bcc_entry.completion = new ContactEntryCompletion(store);
            this.reply_to_entry.completion = new ContactEntryCompletion(store);
        }
    }

    /**
     * Restores the composer's widget state from its draft.
     */
    public async void restore_draft_state_async(Geary.Account account) {
        bool first_email = true;
        
        foreach (Geary.RFC822.MessageID mid in this.in_reply_to) {
            Gee.MultiMap<Geary.Email, Geary.FolderPath?>? email_map;
            try {
                email_map =
                    yield account.local_search_message_id_async(mid, Geary.Email.Field.ENVELOPE,
                    true, null, new Geary.EmailFlags.with(Geary.EmailFlags.DRAFT)); // TODO: Folder blacklist
            } catch (Error error) {
                continue;
            }
            if (email_map == null)
                continue;
            Gee.Set<Geary.Email> emails = email_map.get_keys();
            Geary.Email? email = null;
            foreach (Geary.Email candidate in emails) {
                if (candidate.message_id.equal_to(mid)) {
                    email = candidate;
                    break;
                }
            }
            if (email == null)
                continue;

            // XXX pretty sure we are calling this only to update the
            // composer's internal set of ids - we really shouldn't be
            // messing around with the draft's recipients since the
            // user may have already updated them.
            add_recipients_and_ids(this.compose_type, email, false);

            if (first_email) {
                this.reply_subject = Geary.RFC822.Utils.create_subject_for_reply(email);
                this.forward_subject = Geary.RFC822.Utils.create_subject_for_forward(email);
                first_email = false;
            }
        }
        if (first_email)  // Either no referenced emails, or we don't have them.  Treat as new.
            return;

        if (this.cc == "")
            this.compose_type = ComposeType.REPLY;
        else
            this.compose_type = ComposeType.REPLY_ALL;

        this.to_entry.modified = this.cc_entry.modified = this.bcc_entry.modified = false;
        if (!to_entry.addresses.equal_to(reply_to_addresses))
            this.to_entry.modified = true;
        if (cc != "" && !cc_entry.addresses.equal_to(reply_cc_addresses))
            this.cc_entry.modified = true;
        if (bcc != "")
            this.bcc_entry.modified = true;

        if (in_reply_to.size > 1) {
            this.state = ComposerState.PANED;
        } else if (this.compose_type == ComposeType.FORWARD || this.to_entry.modified
                   || this.cc_entry.modified || this.bcc_entry.modified) {
            this.state = ComposerState.INLINE;
        } else {
            this.state = ComposerState.INLINE_COMPACT;
            // Set recipients in header
            set_header_recipients();
        }
    }

    // This code is in a separate method due to https://bugzilla.gnome.org/show_bug.cgi?id=742621
    // connect_to_draft_manager() is simply for symmetry.  When above bug is fixed, this code can
    // be moved back into open/close methods
    private void disconnect_from_draft_manager() {
        this.draft_manager.notify[Geary.App.DraftManager.PROP_DRAFT_STATE]
            .disconnect(on_draft_state_changed);
        this.draft_manager.notify[Geary.App.DraftManager.PROP_CURRENT_DRAFT_ID]
            .disconnect(on_draft_id_changed);
        this.draft_manager.fatal.disconnect(on_draft_manager_fatal);
    }

    /**
     * Creates and opens the composer's draft manager.
     */
    public async void open_draft_manager_async(
        Geary.EmailIdentifier? editing_draft_id = null,
        Cancellable? cancellable = null)
    throws Error {
        this.draft_save_text = "";
        SimpleAction close_and_save = get_action(ACTION_CLOSE_AND_SAVE);

        close_and_save.set_enabled(false);

        yield close_draft_manager_async(cancellable);

        if (!this.account.information.save_drafts) {
            this.header.save_and_close_button.hide();
            return;
        }

        this.draft_manager = new Geary.App.DraftManager(account);
        try {
            yield this.draft_manager.open_async(editing_draft_id, cancellable);
        } catch (Error err) {
            debug("Unable to open draft manager %s: %s",
                  this.draft_manager.to_string(), err.message);

            this.draft_manager = null;

            throw err;
        }

        close_and_save.set_enabled(true);
        this.header.save_and_close_button.show();

        this.draft_manager.notify[Geary.App.DraftManager.PROP_DRAFT_STATE]
            .connect(on_draft_state_changed);
        this.draft_manager.notify[Geary.App.DraftManager.PROP_CURRENT_DRAFT_ID]
            .connect(on_draft_id_changed);
        this.draft_manager.fatal.connect(on_draft_manager_fatal);
    }

    // Copies the addresses (e.g. From/To/CC) and content from referred into this one
    private void fill_in_from_referred(Geary.Email referred, string? quote) {
        if (this.compose_type != ComposeType.NEW_MESSAGE) {
            add_recipients_and_ids(this.compose_type, referred);
            this.reply_subject = Geary.RFC822.Utils.create_subject_for_reply(referred);
            this.forward_subject = Geary.RFC822.Utils.create_subject_for_forward(referred);
        }
        this.pending_attachments = referred.attachments;
        this.last_quote = quote;
        switch (this.compose_type) {
            case ComposeType.NEW_MESSAGE:
                if (referred.from != null)
                    this.from = referred.from;
                if (referred.to != null)
                    this.to_entry.addresses = referred.to;
                if (referred.cc != null)
                    this.cc_entry.addresses = referred.cc;
                if (referred.bcc != null)
                    this.bcc_entry.addresses = referred.bcc;
                if (referred.in_reply_to != null)
                    this.in_reply_to.add_all(referred.in_reply_to.list);
                if (referred.references != null)
                    this.references = referred.references.to_rfc822_string();
                if (referred.subject != null)
                    this.subject = referred.subject.value;
                try {
                    Geary.RFC822.Message message = referred.get_message();
                    if (message.has_html_body()) {
                        this.body_html = message.get_html_body(null);
                    } else {
                        this.body_html = message.get_plain_body(true, null);
                    }
                } catch (Error error) {
                    debug("Error getting message body: %s", error.message);
                }
            break;

            case ComposeType.REPLY:
            case ComposeType.REPLY_ALL:
                this.subject = reply_subject;
                this.references = Geary.RFC822.Utils.reply_references(referred);
                this.body_html = "\n\n" + Geary.RFC822.Utils.quote_email_for_reply(referred, quote,
                    Geary.RFC822.TextFormat.HTML);
                if (quote != null)
                    this.top_posting = false;
                else
                    this.can_delete_quote = true;
            break;

            case ComposeType.FORWARD:
                this.subject = forward_subject;
                this.body_html = "\n\n" + Geary.RFC822.Utils.quote_email_for_forward(referred, quote,
                    Geary.RFC822.TextFormat.HTML);
            break;
        }
    }

    public void set_focus() {
        if (Geary.String.is_empty(to))
            this.to_entry.grab_focus();
        else if (Geary.String.is_empty(subject))
            this.subject_entry.grab_focus();
        else
            this.editor.grab_focus();
    }

    private bool check_preferred_from_address(Gee.List<Geary.RFC822.MailboxAddress> account_addresses,
        Geary.RFC822.MailboxAddresses? referred_addresses) {
        if (referred_addresses != null) {
            foreach (Geary.RFC822.MailboxAddress address in account_addresses) {
                if (referred_addresses.get_all().contains(address)) {
                    this.from = new Geary.RFC822.MailboxAddresses.single(address);
                    return true;
                }
            }
        }
        return false;
    }

    private void on_load_changed(WebKit.WebView view, WebKit.LoadEvent event) {
        if (event == WebKit.LoadEvent.FINISHED) {
            if (get_realized())
                on_load_finished_and_realized();
            else
                realize.connect(on_load_finished_and_realized);
        }
    }

    private void on_load_finished_and_realized() {
        // This is safe to call even when this connection hasn't been made.
        realize.disconnect(on_load_finished_and_realized);

        if (!Geary.String.is_empty(this.body_html)) {
            this.editor.load_finished_and_realised();
        }

        on_spell_check_changed();
        update_actions();

        this.actions.change_action_state(ACTION_SHOW_EXTENDED, false);
        this.actions.change_action_state(ACTION_COMPOSE_AS_HTML,
            GearyApplication.instance.config.compose_as_html);

        // XXX
        // if (can_delete_quote)
        //     this.editor.selection_changed.connect(() => { this.can_delete_quote = false; });
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
            this.visible_on_attachment_drag_over.add(this.visible_on_attachment_drag_over_child);
            this.visible_on_attachment_drag_over.set_size_request(-1, height);
        } else {
            this.hidden_on_attachment_drag_over.add(this.hidden_on_attachment_drag_over_child);
            this.visible_on_attachment_drag_over.remove(this.visible_on_attachment_drag_over_child);
            this.visible_on_attachment_drag_over.set_size_request(-1, -1);
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
                    add_attachment(File.new_for_uri(uri.strip()));
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

    public Geary.ComposedEmail get_composed_email(DateTime? date_override = null,
        bool only_html = false) {
        Geary.ComposedEmail email = new Geary.ComposedEmail(
            date_override ?? new DateTime.now_local(), from);

        email.to = this.to_entry.addresses ?? email.to;
        email.cc = this.cc_entry.addresses ?? email.cc;
        email.bcc = this.bcc_entry.addresses ?? email.bcc;
        email.reply_to = this.reply_to_entry.addresses ?? email.reply_to;

        if ((this.compose_type == ComposeType.REPLY || this.compose_type == ComposeType.REPLY_ALL) &&
            !this.in_reply_to.is_empty)
            email.in_reply_to =
                new Geary.RFC822.MessageIDList.from_collection(in_reply_to).to_rfc822_string();

        if (!Geary.String.is_empty(this.references))
            email.references = this.references;

        if (!Geary.String.is_empty(this.subject))
            email.subject = this.subject;

        email.attached_files.add_all(this.attached_files);
        email.inline_files.add_all(this.inline_files);
        email.cid_files.set_all(this.cid_files);

        email.img_src_prefix = this.editor.allow_prefix;

        if (actions.get_action_state(ACTION_COMPOSE_AS_HTML).get_boolean() || only_html)
            email.body_html = get_html();
        if (!only_html)
            email.body_text = get_text();

        // User-Agent
        email.mailer = GearyApplication.PRGNAME + "/" + GearyApplication.VERSION;

        return email;
    }

    public override void show_all() {
        base.show_all();
        // Now, hide elements that we don't want shown
        update_from_field();
        this.state = this.state;  // Triggers visibilities
        show_attachments();
    }

    public void change_compose_type(ComposeType new_type, Geary.Email? referred = null,
        string? quote = null) {
        if (referred != null && quote != null && quote != this.last_quote) {
            this.last_quote = quote;
            // Always use reply styling, since forward styling doesn't work for inline quotes
            this.editor.insert_quote(
                Geary.RFC822.Utils.quote_email_for_reply(referred, quote, Geary.RFC822.TextFormat.HTML)
            );

            if (!referred_ids.contains(referred.id)) {
                add_recipients_and_ids(new_type, referred);
                ensure_paned();
            }
        } else if (new_type != this.compose_type) {
            bool recipients_modified = this.to_entry.modified || this.cc_entry.modified || this.bcc_entry.modified;
            switch (new_type) {
                case ComposeType.REPLY:
                case ComposeType.REPLY_ALL:
                    this.subject = this.reply_subject;
                    if (!recipients_modified) {
                        this.to_entry.addresses = reply_to_addresses;
                        this.cc_entry.addresses = (new_type == ComposeType.REPLY_ALL) ?
                            reply_cc_addresses : null;
                        this.to_entry.modified = this.cc_entry.modified = false;
                    } else {
                        this.to_entry.select_region(0, -1);
                    }
                break;

                case ComposeType.FORWARD:
                    if (this.state == ComposerState.INLINE_COMPACT)
                        this.state = ComposerState.INLINE;
                    this.subject = forward_subject;
                    if (!recipients_modified) {
                        this.to = "";
                        this.cc = "";
                        this.to_entry.modified = this.cc_entry.modified = false;
                    } else {
                        this.to_entry.select_region(0, -1);
                    }
                break;

                default:
                    assert_not_reached();
            }
            this.compose_type = new_type;
        }

        this.container.present();
        set_focus();
    }

    private void add_recipients_and_ids(ComposeType type, Geary.Email referred,
        bool modify_headers = true) {
        Gee.List<Geary.RFC822.MailboxAddress> sender_addresses =
            account.information.get_all_mailboxes();

        // Set the preferred from address. New messages should retain
        // the account default and drafts should retain the draft's
        // from addresses, so don't update them here
        if (this.compose_type != ComposeType.NEW_MESSAGE) {
            if (!check_preferred_from_address(sender_addresses, referred.to)) {
                if (!check_preferred_from_address(sender_addresses, referred.cc))
                    if (!check_preferred_from_address(sender_addresses, referred.bcc))
                        check_preferred_from_address(sender_addresses, referred.from);
            }
        }

        // Update the recipient addresses
        Geary.RFC822.MailboxAddresses to_addresses =
            Geary.RFC822.Utils.create_to_addresses_for_reply(referred, sender_addresses);
        Geary.RFC822.MailboxAddresses cc_addresses =
            Geary.RFC822.Utils.create_cc_addresses_for_reply_all(referred, sender_addresses);
        reply_to_addresses = Geary.RFC822.Utils.merge_addresses(reply_to_addresses, to_addresses);
        reply_cc_addresses = Geary.RFC822.Utils.remove_addresses(
            Geary.RFC822.Utils.merge_addresses(reply_cc_addresses, cc_addresses),
            reply_to_addresses);

        if (!modify_headers)
            return;
        
        bool recipients_modified = this.to_entry.modified || this.cc_entry.modified || this.bcc_entry.modified;
        if (!recipients_modified) {
            if (type == ComposeType.REPLY || type == ComposeType.REPLY_ALL)
                this.to_entry.addresses = Geary.RFC822.Utils.merge_addresses(to_entry.addresses,
                    to_addresses);
            if (type == ComposeType.REPLY_ALL)
                this.cc_entry.addresses = Geary.RFC822.Utils.remove_addresses(
                    Geary.RFC822.Utils.merge_addresses(this.cc_entry.addresses, cc_addresses),
                    this.to_entry.addresses);
            else
                this.cc_entry.addresses = Geary.RFC822.Utils.remove_addresses(this.cc_entry.addresses,
                    this.to_entry.addresses);
            this.to_entry.modified = this.cc_entry.modified = false;
        }
        
        in_reply_to.add(referred.message_id);
        referred_ids.add(referred.id);
    }
    
    private void add_signature_and_cursor() {
        string? signature = null;
        
        // If use signature is enabled but no contents are on settings then we'll use ~/.signature, if any
        // otherwise use whatever the user has input in settings dialog
        if (this.account.information.use_email_signature
            && Geary.String.is_empty_or_whitespace(this.account.information.email_signature)) {
            File signature_file = File.new_for_path(Environment.get_home_dir()).get_child(".signature");
            if (!signature_file.query_exists()) {
                set_cursor();
                return;
            }
            
            try {
                FileUtils.get_contents(signature_file.get_path(), out signature);
                if (Geary.String.is_empty_or_whitespace(signature)) {
                    set_cursor();
                    return;
                }
                signature = Geary.HTML.smart_escape(signature, false);
            } catch (Error error) {
                debug("Error reading signature file %s: %s", signature_file.get_path(), error.message);
                set_cursor();
                return;
            }
        } else {
            signature = account.information.email_signature;
            if (Geary.String.is_empty_or_whitespace(signature)) {
                set_cursor();
                return;
            }
            signature = Geary.HTML.smart_escape(signature, true);
        }

        if (this.body_html == null)
            this.body_html = CURSOR + "<br /><br />" + signature;
        else if (top_posting)
            this.body_html = CURSOR + "<br /><br />" + signature + this.body_html;
        else
            this.body_html = this.body_html + CURSOR + "<br /><br />" + signature;
    }

    private void set_cursor() {
        if (top_posting)
            this.body_html = CURSOR + this.body_html;
        else
            this.body_html = this.body_html + CURSOR;
    }

    private bool can_save() {
        return this.draft_manager != null
            && this.draft_manager.is_open
            && this.editor.can_undo()
            && this.account.information.save_drafts;
    }

    public CloseStatus should_close() {
        if (this.is_closing)
            return CloseStatus.PENDING_CLOSE;

        bool try_to_save = can_save();

        this.container.present();
        AlertDialog dialog;
        if (try_to_save) {
            dialog = new TernaryConfirmationDialog(container.top_window,
                _("Do you want to discard this message?"), null, Stock._KEEP, Stock._DISCARD, 
                Gtk.ResponseType.CLOSE, "suggested-action");
        } else {
            dialog = new ConfirmationDialog(container.top_window,
                _("Do you want to discard this message?"), null, Stock._DISCARD, "destructive-action");
        }

        Gtk.ResponseType response = dialog.run();
        if (response == Gtk.ResponseType.CANCEL || response == Gtk.ResponseType.DELETE_EVENT) {
            return CloseStatus.CANCEL_CLOSE; // Cancel
        } else if (response == Gtk.ResponseType.OK) {
            if (try_to_save) {
                save_and_exit_async.begin(); // Save
                return CloseStatus.PENDING_CLOSE;
            } else {
                return CloseStatus.DO_CLOSE;
            }
        } else {
            discard_and_exit_async.begin(); // Discard
            return CloseStatus.PENDING_CLOSE;
        }
    }

    private void on_close(SimpleAction action, Variant? param) {
        if (should_close() == CloseStatus.DO_CLOSE)
            this.container.close_container();
    }

    private void on_close_and_save(SimpleAction action, Variant? param) {
        if (can_save())
            save_and_exit_async.begin();
        else
            on_close(action, param);
    }

    private void on_close_and_discard(SimpleAction action, Variant? param) {
        discard_and_exit_async.begin();
    }

    private void on_detach() {
        if (this.state == ComposerState.DETACHED)
            return;
        Gtk.Widget? focus = this.container.top_window.get_focus();
        this.container.remove_composer();
        ComposerWindow window = new ComposerWindow(this);

        // Workaround a GTK+ crasher, Bug 771812. When the composer is
        // re-parented, its menu_button's popover keeps a reference to
        // the conversation window's viewport, so when that is removed
        // it has a null parent and we crash. To reproduce: Reply
        // inline, detach the composer, then choose a different
        // conversation back in the main window. The workaround here
        // sets a new menu model and hence the menu_button constructs
        // a new popover.
        this.actions.change_action_state(ACTION_COMPOSE_AS_HTML,
            GearyApplication.instance.config.compose_as_html);

        this.state = ComposerWidget.ComposerState.DETACHED;
        if (focus != null && focus.parent.visible) {
            ComposerWindow focus_win = focus.get_toplevel() as ComposerWindow;
            if (focus_win != null && focus_win == window)
                focus.grab_focus();
        } else {
            set_focus();
        }
    }

    public void ensure_paned() {
        if (this.state == ComposerState.PANED || this.state == ComposerState.DETACHED)
            return;
        this.container.remove_composer();
        GearyApplication.instance.controller.main_window.conversation_viewer
            .do_compose(this);
        this.state = ComposerWidget.ComposerState.PANED;
    }

    public void embed_header() {
        if (this.header.parent == null) {
            this.header_area.add(this.header);
            this.header.hexpand = true;
        }
    }

    public void free_header() {
        if (this.header.parent != null)
            this.header.parent.remove(this.header);
    }

    // compares all keys to all tokens according to user-supplied comparison function
    // Returns true if found
    private bool search_tokens(string[] keys, string[] tokens, CompareStringFunc cmp_func,
        out string? found_key, out string? found_token) {
        foreach (string key in keys) {
            foreach (string token in tokens) {
                if (cmp_func(key, token)) {
                    found_key = key;
                    found_token = token;
                    
                    return true;
                }
            }
        }
        
        found_key = null;
        found_token = null;
        
        return false;
    }
    
    private bool email_contains_attachment_keywords() {
        // Filter out all content contained in block quotes
        string filtered = @"$subject\n";
        filtered += this.editor.get_block_quote_representation();
        
        Regex url_regex = null;
        try {
            // Prepare to ignore urls later
            url_regex = new Regex(Geary.HTML.URL_REGEX, RegexCompileFlags.CASELESS);
        } catch (Error error) {
            debug("Error building regex in keyword checker: %s", error.message);
        }
        
        string[] suffix_keys = ATTACHMENT_KEYWORDS_SUFFIX.casefold().split("|");
        string[] full_word_keys = ATTACHMENT_KEYWORDS_LOCALIZED.casefold().split("|");
        
        foreach (string line in filtered.split("\n")) {
            // Stop looking once we hit forwarded content
            if (line.has_prefix("--")) {
                break;
            }
            
            // casefold line, strip start and ending whitespace, then tokenize by whitespace
            string folded = line.casefold().strip();
            string[] tokens = folded.split_set(" \t");
            
            // search for full-word matches
            string? found_key, found_token;
            bool found = search_tokens(full_word_keys, tokens, (key, token) => {
                return key == token;
            }, out found_key, out found_token);
            
            // if not found, search for suffix matches
            if (!found) {
                found = search_tokens(suffix_keys, tokens, (key, token) => {
                    return token.has_suffix(key);
                }, out found_key, out found_token);
            }
            
            if (found) {
                try {
                    // Make sure the match isn't coming from a url
                    if (found_key in url_regex.replace(folded, -1, 0, "")) {
                        return true;
                    }
                } catch (Error error) {
                    debug("Regex replacement error in keyword checker: %s", error.message);
                    return true;
                }
            }
        }
        
        return false;
    }

    private bool should_send() {
        bool has_subject = !Geary.String.is_empty(subject.strip());
        bool has_body = !Geary.String.is_empty(get_html());
        bool has_attachment = this.attached_files.size > 0;

        string? confirmation = null;
        if (!has_subject && !has_body && !has_attachment) {
            confirmation = _("Send message with an empty subject and body?");
        } else if (!has_subject) {
            confirmation = _("Send message with an empty subject?");
        } else if (!has_body && !has_attachment) {
            confirmation = _("Send message with an empty body?");
        } else if (!has_attachment && email_contains_attachment_keywords()) {
            confirmation = _("Send message without an attachment?");
        }
        if (confirmation != null) {
            ConfirmationDialog dialog = new ConfirmationDialog(container.top_window,
                confirmation, null, Stock._OK, "suggested-action");
            return (dialog.run() == Gtk.ResponseType.OK);
        }
        return true;
    }

    // Sends the current message.
    private void on_send(SimpleAction action, Variant? param) {
        if (should_send())
            on_send_async.begin();
    }

    // Used internally by on_send()
    private async void on_send_async() {
        this.container.vanish();
        this.is_closing = true;
        
        this.editor.linkify_document();
        
        // Perform send.
        try {
            yield this.account.send_email_async(get_composed_email());
        } catch (Error e) {
            GLib.message("Error sending email: %s", e.message);
        }
        
        Geary.Nonblocking.Semaphore? semaphore = discard_draft();
        if (semaphore != null) {
            try {
                yield semaphore.wait_async();
            } catch (Error err) {
                // ignored
            }
        }

        // Only close window after draft is deleted; this closes the drafts folder.
        this.container.close_container();
    }

    private void on_draft_state_changed() {
        switch (this.draft_manager.draft_state) {
            case Geary.App.DraftManager.DraftState.STORED:
                this.draft_save_text = DRAFT_SAVED_TEXT;
            break;

            case Geary.App.DraftManager.DraftState.STORING:
                this.draft_save_text = DRAFT_SAVING_TEXT;
            break;

            case Geary.App.DraftManager.DraftState.NOT_STORED:
                this.draft_save_text = "";
            break;

            case Geary.App.DraftManager.DraftState.ERROR:
                this.draft_save_text = DRAFT_ERROR_TEXT;
            break;

            default:
                assert_not_reached();
        }
    }

    private void on_draft_id_changed() {
        draft_id_changed(this.draft_manager.current_draft_id);
    }

    private void on_draft_manager_fatal(Error err) {
        this.draft_save_text = DRAFT_ERROR_TEXT;
    }

    private async void close_draft_manager_async(Cancellable? cancellable) throws Error {
        get_action(ACTION_CLOSE_AND_SAVE).set_enabled(false);
        if (this.draft_manager == null)
            return;

        disconnect_from_draft_manager();

        // drop ref even if close failed
        try {
            yield this.draft_manager.close_async(cancellable);
        } finally {
            this.draft_manager = null;
        }
    }

    // Resets the draft save timeout.
    private void reset_draft_timer() {
        this.draft_save_text = "";
        cancel_draft_timer();
        
        if (can_save())
            draft_save_timeout_id = Timeout.add_seconds(DRAFT_TIMEOUT_SEC, on_save_draft_timeout);
    }

    // Cancels the draft save timeout
    private void cancel_draft_timer() {
        if (this.draft_save_timeout_id == 0)
            return;
        
        Source.remove(this.draft_save_timeout_id);
        this.draft_save_timeout_id = 0;
    }

    private bool on_save_draft_timeout() {
        // this is not rescheduled by the event loop, so kill the timeout id
        this.draft_save_timeout_id = 0;
        
        save_draft();
        
        return false;
    }

    // Note that drafts are NOT "linkified."
    private Geary.Nonblocking.Semaphore? save_draft() {
        // cancel timer in favor of just doing it now
        cancel_draft_timer();
        
        try {
            if (this.draft_manager != null) {
                return this.draft_manager.update(get_composed_email(null, true).to_rfc822_message(),
                    this.draft_flags, null);
            }
        } catch (Error err) {
            GLib.message("Unable to save draft: %s", err.message);
        }
        
        return null;
    }

    private Geary.Nonblocking.Semaphore? discard_draft() {
        // cancel timer in favor of this operation
        cancel_draft_timer();
        
        try {
            if (this.draft_manager != null)
                return this.draft_manager.discard();
        } catch (Error err) {
            GLib.message("Unable to discard draft: %s", err.message);
        }
        
        return null;
    }

    // Used while waiting for draft to save before closing widget.
    private void make_gui_insensitive() {
        this.container.vanish();
        cancel_draft_timer();
    }

    private async void save_and_exit_async() {
        make_gui_insensitive();
        this.is_closing = true;
        
        save_draft();
        try {
            yield close_draft_manager_async(null);
        } catch (Error err) {
            // ignored
        }
        container.close_container();
    }

    private async void discard_and_exit_async() {
        make_gui_insensitive();
        this.is_closing = true;

        discard_draft();
        if (draft_manager != null)
            draft_manager.discard_on_close = true;
        try {
            yield close_draft_manager_async(null);
        } catch (Error err) {
            // ignored
        }

        this.container.close_container();
    }

    // Both adds pending attachments and updates the UI if there are
    // any that were left out, that could have been added manually.
    private void update_pending_attachments(AttachPending include, bool do_add) {
        bool manual_enabled = false;
        if (this.pending_attachments != null) {
            foreach(Geary.Attachment part in this.pending_attachments) {
                try {
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
                        if (part.content_id != null) {
                            this.cid_files[part.content_id] = file;
                            this.editor.add_cid_resource(part.content_id, file);
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
                            !(file in this.attached_files) &&
                            !(file in this.inline_files)) {
                            add_attachment(file, type);
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
        this.header.show_pending_attachments = manual_enabled;
    }

    private void add_attachment(File target,
                                Geary.Mime.DispositionType? disposition = null)
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

        if (disposition != Geary.Mime.DispositionType.INLINE) {
            if (!this.attached_files.add(target)) {
                throw new AttachmentError.DUPLICATE(
                    _("“%s” already attached for delivery.").printf(target.get_path())
                );
            }

            Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            this.attachments_box.pack_start(box);

            /// In the composer, the filename followed by its filesize, i.e. "notes.txt (1.12KB)"
            string label_text = _("%s (%s)").printf(target.get_basename(),
                Files.get_filesize_as_string(target_info.get_size()));
            Gtk.Label label = new Gtk.Label(label_text);
            box.pack_start(label);
            label.halign = Gtk.Align.START;
            label.margin_start = 4;
            label.margin_end = 4;

            Gtk.Button remove_button = new Gtk.Button.with_mnemonic(Stock._REMOVE);
            box.pack_start(remove_button, false, false);
            remove_button.clicked.connect(() => remove_attachment(target, box));
        
            show_attachments();
        } else {
            this.inline_files.add(target);
        }
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
        
        show_attachments();
    }

    private void show_attachments() {
        if (this.attached_files.size > 0 )
            attachments_box.show_all();
        else
            attachments_box.hide();

        update_pending_attachments(this.pending_include, true);
    }

    [GtkCallback]
    private void on_subject_changed() {
        reset_draft_timer();
    }

    private void validate_send_button() {
        get_action(ACTION_SEND).set_enabled(this.to_entry.valid || this.cc_entry.valid || this.bcc_entry.valid);
    }

    private void set_header_recipients() {
        if (this.state == ComposerState.INLINE_COMPACT) {
            bool tocc = !this.to_entry.empty && !this.cc_entry.empty,
                ccbcc = !(this.to_entry.empty && this.cc_entry.empty) && !this.bcc_entry.empty;
            string label = this.to_entry.buffer.text + (tocc ? ", " : "")
                + this.cc_entry.buffer.text + (ccbcc ? ", " : "") + this.bcc_entry.buffer.text;
            StringBuilder tooltip = new StringBuilder();
            if (to_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in this.to_entry.addresses)
                    tooltip.append(_("To: ") + addr.get_full_address() + "\n");
            if (cc_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in this.cc_entry.addresses)
                    tooltip.append(_("Cc: ") + addr.get_full_address() + "\n");
            if (bcc_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in this.bcc_entry.addresses)
                    tooltip.append(_("Bcc: ") + addr.get_full_address() + "\n");
            if (reply_to_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in this.reply_to_entry.addresses)
                    tooltip.append(_("Reply-To: ") + addr.get_full_address() + "\n");
            this.header.set_recipients(label, tooltip.str.slice(0, -1));  // Remove trailing \n
        }

        reset_draft_timer();
    }

    private void on_justify(SimpleAction action, Variant? param) {
        this.editor.execute_editing_command("justify" + param.get_string());
    }

    private void on_action(SimpleAction action, Variant? param) {
        if (!action.enabled)
            return;

        // We need the unprefixed name to send as a command to the editor
        string[] prefixed_action_name = action.get_name().split(".");
        string action_name = prefixed_action_name[prefixed_action_name.length - 1];
        this.editor.execute_editing_command(action_name);
    }

    private void on_cut(SimpleAction action, Variant? param) {
        if (this.container.get_focus() == this.editor)
            this.editor.cut_clipboard();
        else if (this.container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) this.container.get_focus()).cut_clipboard();
    }

    private void on_copy(SimpleAction action, Variant? param) {
        if (this.container.get_focus() == this.editor)
            this.editor.copy_clipboard();
        else if (this.container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) this.container.get_focus()).copy_clipboard();
    }

    private void on_copy_link(SimpleAction action, Variant? param) {
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        c.set_text(this.hover_url, -1);
        c.store();
    }

    private void on_clipboard_text_received(Gtk.Clipboard clipboard, string? text) {
        if (text != null) {
            this.editor.insert_text(text);
        }
    }

    private void on_paste(SimpleAction action, Variant? param) {
        if (this.container.get_focus() == this.editor)
            get_clipboard(Gdk.SELECTION_CLIPBOARD).request_text(on_clipboard_text_received);
        else if (this.container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) this.container.get_focus()).paste_clipboard();
    }

    private void on_paste_with_formatting(SimpleAction action, Variant? param) {
        if (this.container.get_focus() == this.editor)
            this.editor.paste_clipboard();
    }

    private void on_select_all(SimpleAction action, Variant? param) {
        this.editor.select_all();
    }

    private void on_remove_format(SimpleAction action, Variant? param) {
        this.editor.execute_editing_command("removeformat");
        this.editor.execute_editing_command("removeparaformat");
        this.editor.execute_editing_command("unlink");
        this.editor.execute_editing_command_with_argument("backcolor", "#ffffff");
        this.editor.execute_editing_command_with_argument("forecolor", "#000000");
    }

    // Use this for toggle actions, and use the change-state signal to respond to these state changes
    private void on_toggle_action(SimpleAction? action, Variant? param) {
        action.change_state(!action.state.get_boolean());
    }

    private void on_compose_as_html_toggled(SimpleAction? action, Variant? new_state) {
        bool compose_as_html = new_state.get_boolean();
        action.set_state(compose_as_html);

        foreach (string html_action in html_actions)
            get_action(html_action).set_enabled(compose_as_html);
        this.remove_format_button.visible = compose_as_html;

        this.menu_button.menu_model = (compose_as_html) ? this.html_menu : this.plain_menu;

        this.editor.enable_rich_text(compose_as_html);

        GearyApplication.instance.config.compose_as_html = compose_as_html;
    }

    private void on_show_extended_toggled(SimpleAction? action, Variant? new_state) {
        bool show_extended = new_state.get_boolean();
        action.set_state(show_extended);
        this.bcc_label.visible =
            this.bcc_entry.visible =
            this.reply_to_label.visible =
            this.reply_to_entry.visible = show_extended;

        if (show_extended && this.state == ComposerState.INLINE_COMPACT)
            this.state = ComposerState.INLINE;
    }

    private void on_font_family(SimpleAction action, Variant? param) {
        this.editor.execute_editing_command_with_argument(
            "fontname", param.get_string()
        );
        action.set_state(param.get_string());
  }

    private void on_font_size(SimpleAction action, Variant? param) {
        string size = "";
        if (param.get_string() == "small")
            size = "1";
        else if (param.get_string() == "medium")
            size = "3";
        else // Large
            size = "7";

        this.editor.execute_editing_command_with_argument("fontsize", size);
        action.set_state(param.get_string());
    }

    private void on_select_color() {
        Gtk.ColorChooserDialog dialog = new Gtk.ColorChooserDialog(_("Select Color"),
            this.container.top_window);
        if (dialog.run() == Gtk.ResponseType.OK) {
            this.editor.execute_editing_command_with_argument(
                "forecolor", dialog.get_rgba().to_string()
            );
        }
        dialog.destroy();
    }

    private void on_indent(SimpleAction action, Variant? param) {
        on_action(action, param);
        this.editor.undo_blockquote_style();
    }

    private void link_dialog(string link) {
        // Gtk.Dialog dialog = new Gtk.Dialog();
        // bool existing_link = false;

        // // Save information needed to re-establish selection
        // WebKit.DOM.DOMSelection selection = this.editor.get_dom_document().get_default_view().
        //     get_selection();
        // WebKit.DOM.Node anchor_node = selection.anchor_node;
        // long anchor_offset = selection.anchor_offset;
        // WebKit.DOM.Node focus_node = selection.focus_node;
        // long focus_offset = selection.focus_offset;

        // // Allow user to remove link if they're editing an existing one.
        // if (focus_node != null && (focus_node is WebKit.DOM.HTMLAnchorElement ||
        //     focus_node.get_parent_element() is WebKit.DOM.HTMLAnchorElement)) {
        //     existing_link = true;
        //     dialog.add_buttons(Stock._REMOVE, Gtk.ResponseType.REJECT);
        // }

        // dialog.add_buttons(Stock._CANCEL, Gtk.ResponseType.CANCEL, Stock._OK,
        //     Gtk.ResponseType.OK);

        // Gtk.Entry entry = new Gtk.Entry();
        // entry.changed.connect(() => {
        //     // Only allow OK when there's text in the box.
        //     dialog.set_response_sensitive(Gtk.ResponseType.OK,
        //         !Geary.String.is_empty(entry.text.strip()));
        // });

        // dialog.width_request = 350;
        // dialog.get_content_area().spacing = 7;
        // dialog.get_content_area().border_width = 10;
        // dialog.get_content_area().pack_start(new Gtk.Label("Link URL:"));
        // dialog.get_content_area().pack_start(entry);
        // dialog.get_widget_for_response(Gtk.ResponseType.OK).can_default = true;
        // dialog.set_default_response(Gtk.ResponseType.OK);
        // dialog.show_all();

        // entry.set_text(link);
        // entry.activates_default = true;
        // entry.move_cursor(Gtk.MovementStep.BUFFER_ENDS, 0, false);

        // int response = dialog.run();

        // // Re-establish selection, since selecting text in the Entry will de-select all
        // // in the WebView.
        // try {
        //     selection.set_base_and_extent(anchor_node, anchor_offset, focus_node, focus_offset);
        // } catch (Error e) {
        //     debug("Error re-establishing selection: %s", e.message);
        // }

        // if (response == Gtk.ResponseType.OK)
        //     this.editor.execute_editing_command_with_argument("createLink", entry.text);
        // else if (response == Gtk.ResponseType.REJECT)
        //     this.editor.execute_editing_command("unlink");

        // dialog.destroy();

        // Re-bind to anchor links.  This must be done every time link have changed.
        //Util.DOM.bind_event(this.editor,"a", "click", (Callback) on_link_clicked, this);
    }

    private string get_html() {
        return this.editor.get_html();
    }

    private string get_text() {
        return this.editor.get_text();
    }

    private void on_link_activated(ClientWebView view, string uri) {
        if (this.actions.get_action_state(ACTION_COMPOSE_AS_HTML).get_boolean())
            link_dialog(uri);
    }


    private void on_mouse_target_changed(WebKit.WebView web_view,
                                         WebKit.HitTestResult hit_test,
                                         uint modifiers) {
        bool copy_link_enabled = false;
        if (hit_test.context_is_link()) {
            copy_link_enabled = true;
            this.hover_url = hit_test.get_link_uri();
        }
        get_action(ACTION_COPY_LINK).set_enabled(copy_link_enabled);
    }

    private void update_message_overlay_label_style() {
        Gdk.RGBA window_background = container.top_window.get_style_context()
            .get_background_color(Gtk.StateFlags.NORMAL);
        Gdk.RGBA label_background = message_overlay_label.get_style_context()
            .get_background_color(Gtk.StateFlags.NORMAL);
        
        if (label_background == window_background)
            return;
        
        message_overlay_label.get_style_context().changed.disconnect(
            on_message_overlay_label_style_changed);
        message_overlay_label.override_background_color(Gtk.StateFlags.NORMAL, window_background);
        message_overlay_label.get_style_context().changed.connect(
            on_message_overlay_label_style_changed);
    }

    [GtkCallback]
    private void on_message_overlay_label_realize() {
        update_message_overlay_label_style();
    }

    private void on_message_overlay_label_style_changed() {
        update_message_overlay_label_style();
    }

    private void on_spell_check_changed() {
        //this.editor.settings.enable_spell_checking = GearyApplication.instance.config.spell_check;
        //get_action(ACTION_SELECT_DICTIONARY).set_enabled(this.editor.settings.enable_spell_checking);
    }

    // This overrides the keypress handling for the *widget*; the WebView editor's keypress overrides
    // are handled by on_editor_key_press
    public override bool key_press_event(Gdk.EventKey event) {
        update_actions();
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Return":
            case "KP_Enter":
                // always trap Ctrl+Enter/Ctrl+KeypadEnter to prevent the Enter leaking through
                // to the controls, but only send if send is available
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    this.actions.activate_action(ACTION_SEND, null);
                    return true;
                }
            break;
        }
        
        return base.key_press_event(event);
    }

    private bool on_context_menu(WebKit.WebView view,
                                 WebKit.ContextMenu default_menu,
                                 Gdk.Event event,
                                 WebKit.HitTestResult hit_test_result) {
        // Gtk.Menu context_menu = (Gtk.Menu) default_menu;

        // // Keep the spelling menu items
        // foreach (weak Gtk.Widget child in context_menu.get_children()) {
        //     Gtk.MenuItem item = (Gtk.MenuItem) child;
        //     WebKit.ContextMenuAction action = WebKit.context_menu_item_get_action(item);

        //     const WebKit.ContextMenuAction[] spelling_actions = {
        //         WebKit.ContextMenuAction.SPELLING_GUESS,
        //         WebKit.ContextMenuAction.IGNORE_SPELLING,
        //         WebKit.ContextMenuAction.LEARN_SPELLING
        //     };

        //     if (!(action in spelling_actions))
        //         context_menu.remove(item);
        // }

        // // Add our own Menu (but don't add formatting actions if they are disabled).
        // context_menu.insert_action_group("cme", this.actions);
        // GtkUtil.add_g_menu_to_gtk_menu(context_menu, context_menu_model, (label, detailed_action_name) => {
        //     string action_name;
        //     Variant? target;
        //     try {
        //         Action.parse_detailed_name(detailed_action_name, out action_name, out target);
        //         if ("." in action_name) // Remove possible prefixes
        //             action_name = action_name.split(".")[1];
        //     } catch (GLib.Error e) {
        //         debug("Couldn't parse action \"%s\" in context menu".printf(detailed_action_name));
        //     }
        //     return !(action_name in html_actions) || (this.actions.get_action_enabled(action_name));
        // });

        // if (Args.inspector) {
        //     Gtk.MenuItem inspect_item = new Gtk.MenuItem.with_mnemonic(_("_Inspect"));
        //     inspect_item.activate.connect(() => {
        //             this.editor.get_inspector().show();
        //         });
        //     context_menu.append(new Gtk.SeparatorMenuItem());
        //     context_menu.append(inspect_item);
        // }

        // context_menu.show_all();
        // update_actions();
        return false;
    }

    private void on_select_dictionary(SimpleAction action, Variant? param) {
        if (this.spell_check_popover == null) {
            this.spell_check_popover = new SpellCheckPopover(select_dictionary_button);
            this.spell_check_popover.selection_changed.connect((active_langs) => {
                    //this.editor.settings.spell_checking_languages = string.joinv(",", active_langs);
                    GearyApplication.instance.config.spell_check_languages = active_langs;
                });
        }
        this.spell_check_popover.toggle();
    }

    private bool on_editor_key_press(Gdk.EventKey event) {
        // widget's keypress override doesn't receive non-modifier keys when the editor processes
        // them, regardless if true or false is called; this deals with that issue (specifically
        // so Ctrl+Enter will send the message)
        if (event.is_modifier == 0) {
            if (key_press_event(event))
                return true;
        }
        
        if ((event.state & Gdk.ModifierType.MOD1_MASK) != 0)
            return false;
        
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            if (event.keyval == Gdk.Key.Tab) {
                child_focus(Gtk.DirectionType.TAB_FORWARD);
                return true;
            }
            if (event.keyval == Gdk.Key.ISO_Left_Tab) {
                child_focus(Gtk.DirectionType.TAB_BACKWARD);
                return true;
            }
            return false;
        }
        
        if (this.can_delete_quote) {
            this.can_delete_quote = false;
            if (event.keyval == Gdk.Key.BackSpace) {
                this.body_html = null;
                if (this.account.information.use_email_signature)
                    add_signature_and_cursor();
                else
                    set_cursor();
                this.editor.load_html(HTML_BODY, null);
                return true;
            }
        }

        return this.editor.handle_key_press(event);
    }

    /**
     * Helper method, returns a composer action.
     * @param action_name - The name of the action (as found in action_entries)
     */
    public SimpleAction? get_action(string action_name) {
        return this.actions.lookup_action(action_name) as SimpleAction;
    }

    /**
     * Updates the states of the composer's actions and whether they should be enabled.
     */
    private void update_actions() {
        // Basic editor commands
        get_action(ACTION_UNDO).set_enabled(this.editor.can_undo());
        get_action(ACTION_REDO).set_enabled(this.editor.can_redo());
        get_action(ACTION_CUT).set_enabled(this.editor.can_cut_clipboard());
        get_action(ACTION_COPY).set_enabled(this.editor.can_copy_clipboard());
        get_action(ACTION_PASTE).set_enabled(this.editor.can_paste_clipboard());
        get_action(ACTION_PASTE_WITH_FORMATTING).set_enabled(this.editor.can_paste_clipboard()
            && get_action(ACTION_COMPOSE_AS_HTML).state.get_boolean());

        // // Style formatting actions.
        // WebKit.DOM.Document document = this.editor.get_dom_document();
        // WebKit.DOM.DOMWindow window = document.get_default_view();
        // WebKit.DOM.DOMSelection? selection = window.get_selection();
        // if (selection == null)
        //     return;

        // get_action(ACTION_REMOVE_FORMAT).set_enabled(!selection.is_collapsed
        //     && get_action(ACTION_COMPOSE_AS_HTML).state.get_boolean());

        // WebKit.DOM.Element? active = selection.focus_node as WebKit.DOM.Element;
        // if (active == null && selection.focus_node != null)
        //     active = selection.focus_node.get_parent_element();

        // if (active != null) {
        //     WebKit.DOM.CSSStyleDeclaration styles = window.get_computed_style(active, "");

        //     // Font family.
        //     string font_name = styles.get_property_value("font-family").down();
        //     if (font_name.contains("sans") ||
        //         font_name.contains("arial") ||
        //         font_name.contains("trebuchet") ||
        //         font_name.contains("helvetica"))
        //         this.actions.change_action_state(ACTION_FONT_FAMILY, "sans");
        //     else if (font_name.contains("serif") ||
        //         font_name.contains("georgia") ||
        //         font_name.contains("times"))
        //         this.actions.change_action_state(ACTION_FONT_FAMILY, "serif");
        //     else if (font_name.contains("monospace") ||
        //         font_name.contains("courier") ||
        //         font_name.contains("console"))
        //         this.actions.change_action_state(ACTION_FONT_FAMILY, "monospace");

        //     // Font size.
        //     int font_size;
        //     styles.get_property_value("font-size").scanf("%dpx", out font_size);
        //     if (font_size < 11)
        //         this.actions.change_action_state(ACTION_FONT_SIZE, "small");
        //     else if (font_size > 20)
        //         this.actions.change_action_state(ACTION_FONT_SIZE, "large");
        //     else
        //         this.actions.change_action_state(ACTION_FONT_SIZE, "medium");
        // }
    }

    private bool add_account_emails_to_from_list(Geary.Account other_account, bool set_active = false) {
        Geary.RFC822.MailboxAddresses primary_address = new Geary.RFC822.MailboxAddresses.single(
            other_account.information.primary_mailbox);
        this.from_multiple.append_text(primary_address.to_rfc822_string());
        this.from_list.add(new FromAddressMap(other_account, primary_address));
        if (!set_active && this.from.equal_to(primary_address)) {
            this.from_multiple.set_active(this.from_list.size - 1);
            set_active = true;
        }

        if (other_account.information.alternate_mailboxes != null) {
            foreach (Geary.RFC822.MailboxAddress alternate_mailbox in other_account.information.alternate_mailboxes) {
                Geary.RFC822.MailboxAddresses addresses = new Geary.RFC822.MailboxAddresses.single(
                    alternate_mailbox);
                
                // Displayed in the From dropdown to indicate an "alternate email address"
                // for an account.  The first printf argument will be the alternate email
                // address, and the second will be the account's primary email address.
                string display = _("%1$s via %2$s").printf(addresses.to_rfc822_string(), other_account.information.display_name);
                this.from_multiple.append_text(display);
                this.from_list.add(new FromAddressMap(other_account, addresses));
                
                if (!set_active && this.from.equal_to(addresses)) {
                    this.from_multiple.set_active(this.from_list.size - 1);
                    set_active = true;
                }
            }
        }
        return set_active;
    }

    // Updates from combobox contents and visibility, returns true if
    // the from address had to be set
    private bool update_from_field() {
        this.from_multiple.changed.disconnect(on_from_changed);
        this.from_single.visible = this.from_multiple.visible = this.from_label.visible = false;

        Gee.Map<string, Geary.AccountInformation> accounts;
        try {
            accounts = Geary.Engine.instance.get_accounts();
        } catch (Error e) {
            debug("Could not fetch account info: %s", e.message);

            return false;
        }

        // Don't show in inline, compact, or paned modes.
        if (this.state == ComposerState.INLINE || this.state == ComposerState.INLINE_COMPACT ||
            this.state == ComposerState.PANED)
            return false;

        // If there's only one account, show nothing. (From fields are hidden above.)
        if (accounts.size < 1 || (accounts.size == 1 && Geary.traverse<Geary.AccountInformation>(
            accounts.values).first().alternate_mailboxes == null))
            return false;

        this.from_label.visible = true;
        this.from_label.set_mnemonic_widget(this.from_multiple);
        // Composer label (with mnemonic underscore) for the account selector
        // when choosing what address to send a message from.
        this.from_label.set_text_with_mnemonic(_("_From:"));

        this.from_multiple.visible = true;
        this.from_multiple.remove_all();
        this.from_list = new Gee.ArrayList<FromAddressMap>();

        // Always add at least the current account. The var set_active
        // is set to true if the current message's from address has
        // been set in the ComboBox.
        bool set_active = add_account_emails_to_from_list(this.account);
        if (this.compose_type == ComposeType.NEW_MESSAGE) {
            foreach (Geary.AccountInformation info in accounts.values) {
                try {
                    Geary.Account a = Geary.Engine.instance.get_account_instance(info);
                    if (a != this.account)
                        set_active = add_account_emails_to_from_list(a, set_active);
                } catch (Error e) {
                    debug("Error getting account in composer: %s", e.message);
                }
            }
        }

        if (!set_active) {
            // The identity or account that was active before has been
            // removed use the best we can get now (primary address of
            // the account or any other)
            this.from_multiple.set_active(0);
        }

        this.from_multiple.changed.connect(on_from_changed);
        return !set_active;
    }

    private void on_from_changed() {
        bool changed = false;
        try {
            changed = update_from_account();
        } catch (Error err) {
            debug("Unable to update From: Account in composer: %s", err.message);
        }
        
        // if the Geary.Account didn't change and the drafts folder is open(ing), do nothing more;
        // need to check for the drafts folder because opening it in the case of multiple From:
        // is handled here alone, so changed open it if not already
        if (!changed && this.draft_manager != null)
            return;
        
        open_draft_manager_async.begin();
        reset_draft_timer();
    }

    private bool update_from_account() throws Error {
        int index = this.from_multiple.get_active();
        if (index < 0)
            return false;

        assert(this.from_list.size > index);

        Geary.Account new_account = this.from_list.get(index).account;
        from = this.from_list.get(index).from;
        if (new_account == this.account)
            return false;

        this.account = new_account;
        load_entry_completions.begin();

        return true;
    }

    private void on_text_attributes_changed(uint mask) {
        this.actions.change_action_state(
            ACTION_BOLD,
            (mask & WebKit.EditorTypingAttributes.BOLD) == WebKit.EditorTypingAttributes.BOLD
        );
        this.actions.change_action_state(
            ACTION_ITALIC,
            (mask & WebKit.EditorTypingAttributes.ITALIC) == WebKit.EditorTypingAttributes.ITALIC
        );
        this.actions.change_action_state(
            ACTION_UNDERLINE,
            (mask & WebKit.EditorTypingAttributes.UNDERLINE) == WebKit.EditorTypingAttributes.UNDERLINE
        );
        this.actions.change_action_state(
            ACTION_STRIKETHROUGH,
            (mask & WebKit.EditorTypingAttributes.STRIKETHROUGH) == WebKit.EditorTypingAttributes.STRIKETHROUGH
        );
    }

    private void on_add_attachment() {
        AttachmentDialog dialog = new AttachmentDialog(this.container.top_window);
        if (dialog.run() == Gtk.ResponseType.ACCEPT) {
            dialog.hide();
            foreach (File file in dialog.get_files()) {
                try {
                    add_attachment(file, Geary.Mime.DispositionType.ATTACHMENT);
                } catch (Error err) {
                    attachment_failed(err.message);
                    break;
                }
            }
        }
        dialog.destroy();
    }

    private void on_pending_attachments() {
        update_pending_attachments(AttachPending.ALL, true);
    }

    private void on_insert_image(SimpleAction action, Variant? param) {
        AttachmentDialog dialog = new AttachmentDialog(this.container.top_window);
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
                    add_attachment(file, Geary.Mime.DispositionType.INLINE);
                    // Use insertHTML instead of insertImage here so
                    // we can specify a max width inline, preventing
                    // large images from overflowing the view port.
                    this.editor.execute_editing_command_with_argument(
                        "insertHTML",
                        "<img style=\"max-width: 100%\" src=\"%s\">".printf(
                            this.editor.allow_prefix + file.get_uri()
                        )
                    );
                } catch (Error err) {
                    attachment_failed(err.message);
                    break;
                }
            }
        }
        dialog.destroy();
    }

    private void on_insert_link(SimpleAction action, Variant? param) {
        link_dialog("http://");
    }

    // private static void on_link_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
    //     ComposerWidget composer) {
    //     try {
    //         composer.editor.get_dom_document().get_default_view().get_selection().
    //             select_all_children(element);
    //     } catch (Error e) {
    //         debug("Error selecting link: %s", e.message);
    //     }
    // }

}
