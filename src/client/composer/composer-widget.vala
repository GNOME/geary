/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Widget for sending messages.
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
        INLINE_NEW,
        INLINE,
        INLINE_COMPACT
    }
    
    public const string ACTION_UNDO = "undo";
    public const string ACTION_REDO = "redo";
    public const string ACTION_CUT = "cut";
    public const string ACTION_COPY = "copy";
    public const string ACTION_COPY_LINK = "copy link";
    public const string ACTION_PASTE = "paste";
    public const string ACTION_PASTE_FORMAT = "paste with formatting";
    public const string ACTION_BOLD = "bold";
    public const string ACTION_ITALIC = "italic";
    public const string ACTION_UNDERLINE = "underline";
    public const string ACTION_STRIKETHROUGH = "strikethrough";
    public const string ACTION_REMOVE_FORMAT = "removeformat";
    public const string ACTION_INDENT = "indent";
    public const string ACTION_OUTDENT = "outdent";
    public const string ACTION_JUSTIFY_LEFT = "justifyleft";
    public const string ACTION_JUSTIFY_RIGHT = "justifyright";
    public const string ACTION_JUSTIFY_CENTER = "justifycenter";
    public const string ACTION_JUSTIFY_FULL = "justifyfull";
    public const string ACTION_MENU = "menu";
    public const string ACTION_COLOR = "color";
    public const string ACTION_INSERT_LINK = "insertlink";
    public const string ACTION_COMPOSE_AS_HTML = "compose as html";
    public const string ACTION_SHOW_EXTENDED = "show extended";
    public const string ACTION_CLOSE = "close";
    public const string ACTION_DETACH = "detach";
    public const string ACTION_SEND = "send";
    public const string ACTION_ADD_ATTACHMENT = "add attachment";
    public const string ACTION_ADD_ORIGINAL_ATTACHMENTS = "add original attachments";
    
    private const string DRAFT_SAVED_TEXT = _("Saved");
    private const string DRAFT_SAVING_TEXT = _("Saving");
    private const string DRAFT_ERROR_TEXT = _("Error saving");
    
    private const string URI_LIST_MIME_TYPE = "text/uri-list";
    private const string FILE_URI_PREFIX = "file://";
    private const string BODY_ID = "message-body";
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
        .embedded #message-body {
            min-height: 200px;
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
        <div id="message-body" contenteditable="true"></div>
        </body></html>""";
    private const string CURSOR = "<span id=\"cursormarker\"></span>";
    
    private const int DRAFT_TIMEOUT_SEC = 10;
    
    public const string ATTACHMENT_KEYWORDS_SUFFIX = ".doc|.pdf|.xls|.ppt|.rtf|.pps";
    
    // A list of keywords, separated by pipe ("|") characters, that suggest an attachment; since
    // this is full-word checking, include all variants of each word.  No spaces are allowed.
    public const string ATTACHMENT_KEYWORDS_LOCALIZED = _("attach|attaching|attaches|attachment|attachments|attached|enclose|enclosed|enclosing|encloses|enclosure|enclosures");
    
    private delegate bool CompareStringFunc(string key, string token);
    
    public Geary.Account account { get; private set; }
    
    public string from { get; set; }
    
    public string to {
        get { return to_entry.get_text(); }
        set { to_entry.set_text(value); }
    }
    
    public string cc {
        get { return cc_entry.get_text(); }
        set { cc_entry.set_text(value); }
    }
    
    public string bcc {
        get { return bcc_entry.get_text(); }
        set { bcc_entry.set_text(value); }
    }

    public string reply_to {
        get { return reply_to_entry.get_text(); }
        set { reply_to_entry.set_text(value); }
    }
    
    public Gee.Set<Geary.RFC822.MessageID> in_reply_to = new Gee.HashSet<Geary.RFC822.MessageID>();
    public string references { get; set; }
    
    public string subject {
        get { return subject_entry.get_text(); }
        set { subject_entry.set_text(value); }
    }
    
    public string message {
        owned get { return get_html(); }
        set {
            body_html = value;
            editor.load_string(HTML_BODY, "text/html", "UTF8", "");
        }
    }
    
    public bool compose_as_html {
        get { return ((Gtk.ToggleAction) actions.get_action(ACTION_COMPOSE_AS_HTML)).active; }
        set { ((Gtk.ToggleAction) actions.get_action(ACTION_COMPOSE_AS_HTML)).active = value; }
    }

    public bool show_extended {
        get { return ((Gtk.ToggleAction) actions.get_action(ACTION_SHOW_EXTENDED)).active; }
        set { ((Gtk.ToggleAction) actions.get_action(ACTION_SHOW_EXTENDED)).active = value; }
    }
    
    public ComposerState state { get; set; }
    
    public ComposeType compose_type { get; private set; default = ComposeType.NEW_MESSAGE; }
    
    public Gee.Set<Geary.EmailIdentifier> referred_ids = new Gee.HashSet<Geary.EmailIdentifier>();
    
    public bool blank {
        get {
            return to_entry.empty && cc_entry.empty && bcc_entry.empty && reply_to_entry.empty &&
                subject_entry.buffer.length == 0 && !editor.can_undo() && attachment_files.size == 0;
        }
    }
    
    public ComposerHeaderbar header { get; private set; }
    
    public string draft_save_text { get; private set; }
    
    private ContactListStore? contact_list_store = null;
    
    private string? body_html = null;
    private Gee.Set<File> attachment_files = new Gee.HashSet<File>(Geary.Files.nullable_hash,
        Geary.Files.nullable_equal);
    
    private Gtk.Builder builder;
    private Gtk.Label from_label;
    private Gtk.Label from_single;
    private Gtk.ComboBoxText from_multiple = new Gtk.ComboBoxText();
    private EmailEntry to_entry;
    private EmailEntry cc_entry;
    private Gtk.Label bcc_label;
    private EmailEntry bcc_entry;
    private Gtk.Label reply_to_label;
    private EmailEntry reply_to_entry;
    public Gtk.Entry subject_entry;
    private Gtk.Label message_overlay_label;
    private Gtk.Box attachments_box;
    private Gtk.Alignment hidden_on_attachment_drag_over;
    private Gtk.Alignment visible_on_attachment_drag_over;
    private Gtk.Widget hidden_on_attachment_drag_over_child;
    private Gtk.Widget visible_on_attachment_drag_over_child;
    
    private Gtk.Menu menu = new Gtk.Menu();
    private Gtk.RadioMenuItem font_small;
    private Gtk.RadioMenuItem font_medium;
    private Gtk.RadioMenuItem font_large;
    private Gtk.RadioMenuItem font_sans;
    private Gtk.RadioMenuItem font_serif;
    private Gtk.RadioMenuItem font_monospace;
    private Gtk.MenuItem color_item;
    private Gtk.MenuItem html_item;
    private Gtk.MenuItem html_item2;
    private Gtk.MenuItem extended_item;
    
    private Gtk.ActionGroup actions;
    private string? hover_url = null;
    private bool action_flag = false;
    private bool is_attachment_overlay_visible = false;
    private Gee.List<Geary.Attachment>? pending_attachments = null;
    private Geary.RFC822.MailboxAddresses reply_to_addresses;
    private Geary.RFC822.MailboxAddresses reply_cc_addresses;
    private string reply_subject = "";
    private string forward_subject = "";
    private bool top_posting = true;
    private string? last_quote = null;
    
    private Geary.App.DraftManager? draft_manager = null;
    private Geary.EmailIdentifier? editing_draft_id = null;
    private Geary.EmailFlags draft_flags = new Geary.EmailFlags.with(Geary.EmailFlags.DRAFT);
    private uint draft_save_timeout_id = 0;
    
    public WebKit.WebView editor;
    // We need to keep a reference to the edit-fixer in composer-window, so it doesn't get
    // garbage-collected.
    private WebViewEditFixer edit_fixer;
    public Gtk.UIManager ui;
    private ComposerContainer container {
        get { return (ComposerContainer) parent; }
    }
    
    public ComposerWidget(Geary.Account account, ComposeType compose_type,
        Geary.Email? referred = null, string? quote = null, bool is_referred_draft = false) {
        this.account = account;
        this.compose_type = compose_type;
        if (compose_type == ComposeType.NEW_MESSAGE)
            state = ComposerState.INLINE_NEW;
        else if (compose_type == ComposeType.FORWARD)
            state = ComposerState.INLINE;
        else
            state = ComposerState.INLINE_COMPACT;
        
        setup_drag_destination(this);
        
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK);
        builder = GearyApplication.instance.create_builder("composer.glade");
        
        Gtk.Box box = builder.get_object("composer") as Gtk.Box;
        attachments_box = builder.get_object("attachments_box") as Gtk.Box;
        hidden_on_attachment_drag_over = (Gtk.Alignment) builder.get_object("hidden_on_attachment_drag_over");
        hidden_on_attachment_drag_over_child = (Gtk.Widget) builder.get_object("hidden_on_attachment_drag_over_child");
        visible_on_attachment_drag_over = (Gtk.Alignment) builder.get_object("visible_on_attachment_drag_over");
        visible_on_attachment_drag_over_child = (Gtk.Widget) builder.get_object("visible_on_attachment_drag_over_child");
        visible_on_attachment_drag_over.remove(visible_on_attachment_drag_over_child);
        
        Gtk.Widget recipients = builder.get_object("recipients") as Gtk.Widget;
        bind_property("state", recipients, "visible", BindingFlags.SYNC_CREATE,
            (binding, source_value, ref target_value) => {
                target_value = (state != ComposerState.INLINE_COMPACT);
                return true;
            });
        string[] subject_elements = {"subject label", "subject"};
        foreach (string name in subject_elements) {
            Gtk.Widget widget = builder.get_object(name) as Gtk.Widget;
            bind_property("state", widget, "visible", BindingFlags.SYNC_CREATE,
                (binding, source_value, ref target_value) => {
                    target_value = (state != ComposerState.INLINE);
                    return true;
                });
        }
        notify["state"].connect((s, p) => { update_from_field(); });
        
        from_label = (Gtk.Label) builder.get_object("from label");
        from_single = (Gtk.Label) builder.get_object("from_single");
        from_multiple = (Gtk.ComboBoxText) builder.get_object("from_multiple");
        to_entry = new EmailEntry(this);
        (builder.get_object("to") as Gtk.EventBox).add(to_entry);
        cc_entry = new EmailEntry(this);
        (builder.get_object("cc") as Gtk.EventBox).add(cc_entry);
        bcc_entry = new EmailEntry(this);
        (builder.get_object("bcc") as Gtk.EventBox).add(bcc_entry);
        reply_to_entry = new EmailEntry(this);
        (builder.get_object("reply to") as Gtk.EventBox).add(reply_to_entry);
        
        Gtk.Label to_label = (Gtk.Label) builder.get_object("to label");
        Gtk.Label cc_label = (Gtk.Label) builder.get_object("cc label");
        bcc_label = (Gtk.Label) builder.get_object("bcc label");
        reply_to_label = (Gtk.Label) builder.get_object("reply to label");
        to_label.set_mnemonic_widget(to_entry);
        cc_label.set_mnemonic_widget(cc_entry);
        bcc_label.set_mnemonic_widget(bcc_entry);
        reply_to_label.set_mnemonic_widget(reply_to_entry);

        to_entry.margin_top = cc_entry.margin_top = bcc_entry.margin_top = reply_to_entry.margin_top = 6;
        
        // TODO: It would be nicer to set the completions inside the EmailEntry constructor. But in
        // testing, this can cause non-deterministic segfaults. Investigate why, and fix if possible.
        set_entry_completions();
        subject_entry = builder.get_object("subject") as Gtk.Entry;
        Gtk.Alignment message_area = builder.get_object("message area") as Gtk.Alignment;
        actions = builder.get_object("compose actions") as Gtk.ActionGroup;
        // Can only happen after actions exits
        compose_as_html = GearyApplication.instance.config.compose_as_html;
        
        header = new ComposerHeaderbar(actions);
        Gtk.Alignment header_area = (Gtk.Alignment) builder.get_object("header_area");
        header_area.add(header);
        bind_property("state", header, "state", BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        
        // Listen to account signals to update from menu.
        Geary.Engine.instance.account_available.connect(update_from_field);
        Geary.Engine.instance.account_unavailable.connect(update_from_field);
        
        Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        Gtk.Overlay message_overlay = new Gtk.Overlay();
        message_overlay.add(scroll);
        message_area.add(message_overlay);
        
        message_overlay_label = new Gtk.Label(null);
        message_overlay_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        message_overlay_label.halign = Gtk.Align.START;
        message_overlay_label.valign = Gtk.Align.END;
        message_overlay_label.realize.connect(on_message_overlay_label_realize);
        message_overlay.add_overlay(message_overlay_label);
        
        subject_entry.changed.connect(on_subject_changed);
        to_entry.changed.connect(validate_send_button);
        cc_entry.changed.connect(validate_send_button);
        bcc_entry.changed.connect(validate_send_button);
        reply_to_entry.changed.connect(validate_send_button);
        
        if (get_direction () == Gtk.TextDirection.RTL) {
            actions.get_action(ACTION_INDENT).icon_name = "format-indent-more-rtl-symbolic";
            actions.get_action(ACTION_OUTDENT).icon_name = "format-indent-less-rtl-symbolic";
        } else {
            actions.get_action(ACTION_INDENT).icon_name = "format-indent-more-symbolic";
            actions.get_action(ACTION_OUTDENT).icon_name = "format-indent-less-symbolic";
        }
        
        ComposerToolbar composer_toolbar = new ComposerToolbar(actions, menu);
        Gtk.Alignment toolbar_area = (Gtk.Alignment) builder.get_object("toolbar area");
        toolbar_area.add(composer_toolbar);
        bind_property("draft-save-text", composer_toolbar, "draft-save-text", BindingFlags.SYNC_CREATE);
        
        actions.get_action(ACTION_UNDO).activate.connect(on_action);
        actions.get_action(ACTION_REDO).activate.connect(on_action);
        
        actions.get_action(ACTION_CUT).activate.connect(on_cut);
        actions.get_action(ACTION_COPY).activate.connect(on_copy);
        actions.get_action(ACTION_COPY_LINK).activate.connect(on_copy_link);
        actions.get_action(ACTION_PASTE).activate.connect(on_paste);
        actions.get_action(ACTION_PASTE_FORMAT).activate.connect(on_paste_with_formatting);
        
        actions.get_action(ACTION_BOLD).activate.connect(on_formatting_action);
        actions.get_action(ACTION_ITALIC).activate.connect(on_formatting_action);
        actions.get_action(ACTION_UNDERLINE).activate.connect(on_formatting_action);
        actions.get_action(ACTION_STRIKETHROUGH).activate.connect(on_formatting_action);
        
        actions.get_action(ACTION_REMOVE_FORMAT).activate.connect(on_remove_format);
        actions.get_action(ACTION_COMPOSE_AS_HTML).activate.connect(on_compose_as_html);
        actions.get_action(ACTION_SHOW_EXTENDED).activate.connect(on_show_extended);
        
        actions.get_action(ACTION_INDENT).activate.connect(on_indent);
        actions.get_action(ACTION_OUTDENT).activate.connect(on_action);
        
        actions.get_action(ACTION_JUSTIFY_LEFT).activate.connect(on_formatting_action);
        actions.get_action(ACTION_JUSTIFY_RIGHT).activate.connect(on_formatting_action);
        actions.get_action(ACTION_JUSTIFY_CENTER).activate.connect(on_formatting_action);
        actions.get_action(ACTION_JUSTIFY_FULL).activate.connect(on_formatting_action);
        
        actions.get_action(ACTION_COLOR).activate.connect(on_select_color);
        actions.get_action(ACTION_INSERT_LINK).activate.connect(on_insert_link);
        
        actions.get_action(ACTION_CLOSE).activate.connect(on_close);
        
        actions.get_action(ACTION_DETACH).activate.connect(on_detach);
        actions.get_action(ACTION_SEND).activate.connect(on_send);
        actions.get_action(ACTION_ADD_ATTACHMENT).activate.connect(on_add_attachment_button_clicked);
        actions.get_action(ACTION_ADD_ORIGINAL_ATTACHMENTS).activate.connect(on_pending_attachments_button_clicked);
        
        ui = new Gtk.UIManager();
        ui.insert_action_group(actions, 0);
        GearyApplication.instance.load_ui_file_for_manager(ui, "composer_accelerators.ui");
        
        add_extra_accelerators();
        
        from = account.information.get_from().to_rfc822_string();
        update_from_field();
        from_multiple.changed.connect(on_from_changed);
        
        if (referred != null) {
            add_recipients_and_ids(compose_type, referred);
            reply_subject = Geary.RFC822.Utils.create_subject_for_reply(referred);
            forward_subject = Geary.RFC822.Utils.create_subject_for_forward(referred);
            last_quote = quote;
            switch (compose_type) {
                case ComposeType.NEW_MESSAGE:
                    if (referred.to != null)
                        to_entry.addresses = referred.to;
                    if (referred.cc != null)
                        cc_entry.addresses = referred.cc;
                    if (referred.bcc != null)
                        bcc_entry.addresses = referred.bcc;
                    if (referred.in_reply_to != null)
                        in_reply_to.add_all(referred.in_reply_to.list);
                    if (referred.references != null)
                        references = referred.references.to_rfc822_string();
                    if (referred.subject != null)
                        subject = referred.subject.value;
                    try {
                        body_html = referred.get_message().get_body(true);
                    } catch (Error error) {
                        debug("Error getting message body: %s", error.message);
                    }
                    
                    if (is_referred_draft)
                        editing_draft_id = referred.id;
                    
                    add_attachments(referred.attachments);
                break;
                
                case ComposeType.REPLY:
                case ComposeType.REPLY_ALL:
                    subject = reply_subject;
                    references = Geary.RFC822.Utils.reply_references(referred);
                    body_html = "\n\n" + Geary.RFC822.Utils.quote_email_for_reply(referred, quote, true);
                    pending_attachments = referred.attachments;
                    if (quote != null)
                        top_posting = false;
                break;
                
                case ComposeType.FORWARD:
                    subject = forward_subject;
                    body_html = "\n\n" + Geary.RFC822.Utils.quote_email_for_forward(referred, quote, true);
                    add_attachments(referred.attachments);
                    pending_attachments = referred.attachments;
                break;
            }
        }
        
        // only add signature if the option is actually set and if this is not a draft
        if (account.information.use_email_signature && !is_referred_draft)
            add_signature_and_cursor();
        else
            set_cursor();
        
        editor = new StylishWebView();
        edit_fixer = new WebViewEditFixer(editor);

        editor.load_finished.connect(on_load_finished);
        editor.hovering_over_link.connect(on_hovering_over_link);
        editor.context_menu.connect(on_context_menu);
        editor.move_focus.connect(update_actions);
        editor.copy_clipboard.connect(update_actions);
        editor.cut_clipboard.connect(update_actions);
        editor.paste_clipboard.connect(update_actions);
        editor.undo.connect(update_actions);
        editor.redo.connect(update_actions);
        editor.selection_changed.connect(update_actions);
        editor.key_press_event.connect(on_editor_key_press);
        editor.user_changed_contents.connect(reset_draft_timer);
        
        // only do this after setting body_html
        editor.load_string(HTML_BODY, "text/html", "UTF8", "");
        
        editor.navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        editor.new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        
        GearyApplication.instance.config.settings.changed[Configuration.SPELL_CHECK_KEY].connect(
            on_spell_check_changed);
        
        // Font family menu items.
        font_sans = new Gtk.RadioMenuItem(new SList<Gtk.RadioMenuItem>());
        font_sans.activate.connect(on_font_sans);
        font_sans.related_action = ui.get_action("ui/font_sans");
        font_serif = new Gtk.RadioMenuItem.from_widget(font_sans);
        font_serif.activate.connect(on_font_serif);
        font_serif.related_action = ui.get_action("ui/font_serif");
        font_monospace = new Gtk.RadioMenuItem.from_widget(font_sans);
        font_monospace.related_action = ui.get_action("ui/font_monospace");
        font_monospace.activate.connect(on_font_monospace);
        
        // Font size menu items.
        font_small = new Gtk.RadioMenuItem(new SList<Gtk.RadioMenuItem>());
        font_small.related_action = ui.get_action("ui/font_small");
        font_small.activate.connect(on_font_size_small);
        font_medium = new Gtk.RadioMenuItem.from_widget(font_small);
        font_medium.related_action = ui.get_action("ui/font_medium");
        font_medium.activate.connect(on_font_size_medium);
        font_large = new Gtk.RadioMenuItem.from_widget(font_small);
        font_large.related_action = ui.get_action("ui/font_large");
        font_large.activate.connect(on_font_size_large);
        
        color_item = new Gtk.MenuItem();
        color_item.related_action = ui.get_action("ui/color");
        html_item = new Gtk.CheckMenuItem();
        html_item.related_action = ui.get_action("ui/htmlcompose");
        extended_item = new Gtk.CheckMenuItem();
        extended_item.related_action = ui.get_action("ui/extended");
        
        html_item2 = new Gtk.CheckMenuItem();
        html_item2.related_action = ui.get_action("ui/htmlcompose");
        
        WebKit.WebSettings s = editor.settings;
        s.enable_spell_checking = GearyApplication.instance.config.spell_check;
        s.auto_load_images = false;
        s.enable_scripts = false;
        s.enable_java_applet = false;
        s.enable_plugins = false;
        editor.settings = s;
        
        scroll.add(editor);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        add(box);
        validate_send_button();

        // Place the message area before the compose toolbar in the focus chain, so that
        // the user can tab directly from the Subject: field to the message area.
        List<Gtk.Widget> chain = new List<Gtk.Widget>();
        chain.append(hidden_on_attachment_drag_over);
        chain.append(message_area);
        chain.append(composer_toolbar);
        chain.append(attachments_box);
        box.set_focus_chain(chain);
        
        // If there's only one account, open the drafts manager.  If there's more than one account,
        // the drafts manager will be opened by on_from_changed().
        if (!from_multiple.visible)
            open_draft_manager_async.begin(null);
        
        destroy.connect(() => { close_draft_manager_async.begin(null); });
    }
    
    public ComposerWidget.from_mailto(Geary.Account account, string mailto) {
        this(account, ComposeType.NEW_MESSAGE);
        
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
                to = "%s,%s".printf(email, Geary.Collection.get_first(headers.get("to")));
            else if (email.length > 0)
                to = email;
            else if (headers.contains("to"))
                to = Geary.Collection.get_first(headers.get("to"));
            
            if (headers.contains("cc"))
                cc = Geary.Collection.get_first(headers.get("cc"));
            
            if (headers.contains("bcc"))
                bcc = Geary.Collection.get_first(headers.get("bcc"));
            
            if (headers.contains("subject"))
                subject = Geary.Collection.get_first(headers.get("subject"));
            
            if (headers.contains("body"))
                body_html = Geary.HTML.preserve_whitespace(Geary.HTML.escape_markup(
                    Geary.Collection.get_first(headers.get("body"))));
            
            foreach (string attachment in headers.get("attach"))
                add_attachment(File.new_for_commandline_arg(attachment));
            foreach (string attachment in headers.get("attachment"))
                add_attachment(File.new_for_commandline_arg(attachment));
        }
    }
    
    public void set_focus() {
        if (Geary.String.is_empty(to)) {
            to_entry.grab_focus();
        } else if (Geary.String.is_empty(subject)) {
            subject_entry.grab_focus();
        } else {
            editor.grab_focus();
        }
    }
    
    private void on_load_finished(WebKit.WebFrame frame) {
        WebKit.DOM.Document document = editor.get_dom_document();
        WebKit.DOM.HTMLElement? body = document.get_element_by_id(BODY_ID) as WebKit.DOM.HTMLElement;
        assert(body != null);

        if (!Geary.String.is_empty(body_html)) {
            try {
                body.set_inner_html(body_html);
            } catch (Error e) {
                debug("Failed to load prefilled body: %s", e.message);
            }
        }
        body.focus();  // Focus within the HTML document

        // Set cursor at appropriate position
        try {
            WebKit.DOM.Element? cursor = document.get_element_by_id("cursormarker");
            if (cursor != null) {
                WebKit.DOM.Range range = document.create_range();
                range.select_node_contents(cursor);
                range.collapse(false);
                WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
                selection.remove_all_ranges();
                selection.add_range(range);
                cursor.parent_element.remove_child(cursor);
            }
        } catch (Error error) {
            debug("Error setting cursor at end of text: %s", error.message);
        }

        protect_blockquote_styles();
        
        set_focus();  // Focus in the GTK widget hierarchy
        
        // Ensure the editor is in correct mode re HTML
        on_compose_as_html();

        bind_event(editor,"a", "click", (Callback) on_link_clicked, this);
        update_actions();
        on_show_extended();
    }
    
    // Glade only allows one accelerator per-action. This method adds extra accelerators not defined
    // in the Glade file.
    private void add_extra_accelerators() {
        GtkUtil.add_accelerator(ui, actions, "Escape", ACTION_CLOSE);
    }
    
    private void setup_drag_destination(Gtk.Widget destination) {
        const Gtk.TargetEntry[] target_entries = { { URI_LIST_MIME_TYPE, 0, 0 } };
        Gtk.drag_dest_set(destination, Gtk.DestDefaults.MOTION | Gtk.DestDefaults.HIGHLIGHT,
            target_entries, Gdk.DragAction.COPY);
        destination.drag_data_received.connect(on_drag_data_received);
        destination.drag_drop.connect(on_drag_drop);
        destination.drag_motion.connect(on_drag_motion);
        destination.drag_leave.connect(on_drag_leave);
    }
    
    private void show_attachment_overlay(bool visible) {
        if (is_attachment_overlay_visible == visible)
            return;
            
        is_attachment_overlay_visible = visible;
        
        // If we just make the widget invisible, it can still intercept drop signals. So we
        // completely remove it instead.
        if (visible) {
            int height = hidden_on_attachment_drag_over.get_allocated_height();
            hidden_on_attachment_drag_over.remove(hidden_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.add(visible_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.set_size_request(-1, height);
        } else {
            hidden_on_attachment_drag_over.add(hidden_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.remove(visible_on_attachment_drag_over_child);
            visible_on_attachment_drag_over.set_size_request(-1, -1);
        }
   }
    
    private bool on_drag_motion() {
        show_attachment_overlay(true);
        return false;
    }
    
    private void on_drag_leave() {
        show_attachment_overlay(false);
    }
    
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
                
                add_attachment(File.new_for_uri(uri.strip()));
            }
        }
        
        Gtk.drag_finish(context, dnd_success, false, time_);
    }
    
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
            date_override ?? new DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.from_rfc822_string(from)
        );
        
        if (to_entry.addresses != null)
            email.to = to_entry.addresses;
        
        if (cc_entry.addresses != null)
            email.cc = cc_entry.addresses;
        
        if (bcc_entry.addresses != null)
            email.bcc = bcc_entry.addresses;

        if (reply_to_entry.addresses != null)
            email.reply_to = reply_to_entry.addresses;
        
        if ((compose_type == ComposeType.REPLY || compose_type == ComposeType.REPLY_ALL) &&
            !in_reply_to.is_empty)
            email.in_reply_to =
                new Geary.RFC822.MessageIDList.from_collection(in_reply_to).to_rfc822_string();
        
        if (!Geary.String.is_empty(references))
            email.references = references;
        
        if (!Geary.String.is_empty(subject))
            email.subject = subject;
        
        email.attachment_files.add_all(attachment_files);
        
        if (compose_as_html || only_html)
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
        state = state;  // Triggers visibilities
        show_attachments();
    }
    
    public void change_compose_type(ComposeType new_type, Geary.Email? referred = null,
        string? quote = null) {
        if (referred != null && quote != null && quote != last_quote) {
            last_quote = quote;
            WebKit.DOM.Document document = editor.get_dom_document();
            // Always use reply styling, since forward styling doesn't work for inline quotes
            document.exec_command("insertHTML", false,
                Geary.RFC822.Utils.quote_email_for_reply(referred, quote, true));
            
            if (!referred_ids.contains(referred.id))
                add_recipients_and_ids(new_type, referred);
        } else if (new_type != compose_type) {
            bool recipients_modified = to_entry.modified || cc_entry.modified || bcc_entry.modified;
            switch (new_type) {
                case ComposeType.REPLY:
                case ComposeType.REPLY_ALL:
                    subject = reply_subject;
                    if (!recipients_modified) {
                        to_entry.addresses = reply_to_addresses;
                        cc_entry.addresses = (new_type == ComposeType.REPLY_ALL) ?
                            reply_cc_addresses : null;
                        to_entry.modified = cc_entry.modified = false;
                    } else {
                        to_entry.select_region(0, -1);
                    }
                break;
                
                case ComposeType.FORWARD:
                    state = ComposerState.INLINE;
                    subject = forward_subject;
                    if (!recipients_modified) {
                        to = "";
                        cc = "";
                        to_entry.modified = cc_entry.modified = false;
                    } else {
                        to_entry.select_region(0, -1);
                    }
                break;
                
                default:
                    assert_not_reached();
            }
            compose_type = new_type;
        }
        
        container.present();
        set_focus();
    }
    
    private void add_recipients_and_ids(ComposeType type, Geary.Email referred) {
        string? sender_address = account.information.get_mailbox_address().address;
        Geary.RFC822.MailboxAddresses to_addresses =
            Geary.RFC822.Utils.create_to_addresses_for_reply(referred, sender_address);
        Geary.RFC822.MailboxAddresses cc_addresses =
            Geary.RFC822.Utils.create_cc_addresses_for_reply_all(referred, sender_address);
        reply_to_addresses = Geary.RFC822.Utils.merge_addresses(reply_to_addresses, to_addresses);
        reply_cc_addresses = Geary.RFC822.Utils.remove_addresses(
            Geary.RFC822.Utils.merge_addresses(reply_cc_addresses, cc_addresses),
            reply_to_addresses);
        
        bool recipients_modified = to_entry.modified || cc_entry.modified || bcc_entry.modified;
        if (!recipients_modified) {
            if (type == ComposeType.REPLY || type == ComposeType.REPLY_ALL)
                to_entry.addresses = Geary.RFC822.Utils.merge_addresses(to_entry.addresses,
                    to_addresses);
            if (type == ComposeType.REPLY_ALL)
                cc_entry.addresses = Geary.RFC822.Utils.remove_addresses(
                    Geary.RFC822.Utils.merge_addresses(cc_entry.addresses, cc_addresses),
                    to_entry.addresses);
            else
                cc_entry.addresses = Geary.RFC822.Utils.remove_addresses(cc_entry.addresses,
                    to_entry.addresses);
            to_entry.modified = cc_entry.modified = false;
        }
        
        in_reply_to.add(referred.message_id);
        referred_ids.add(referred.id);
    }
    
    private void add_signature_and_cursor() {
        string? signature = null;
        
        // If use signature is enabled but no contents are on settings then we'll use ~/.signature, if any
        // otherwise use whatever the user has input in settings dialog
        if (account.information.use_email_signature && Geary.String.is_empty_or_whitespace(account.information.email_signature)) {
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
            } catch (Error error) {
                debug("Error reading signature file %s: %s", signature_file.get_path(), error.message);
                set_cursor();
                return;
            }
        } else {
            signature = account.information.email_signature;
            if(Geary.String.is_empty_or_whitespace(signature)) {
                set_cursor();
                return;
            }
        }
        
        signature = Geary.HTML.escape_markup(signature);
        
        if (body_html == null)
            body_html = CURSOR + Geary.HTML.preserve_whitespace("\n\n" + signature);
        else if (top_posting)
            body_html = CURSOR + Geary.HTML.preserve_whitespace("\n\n" + signature) + body_html;
        else
            body_html = body_html + CURSOR + Geary.HTML.preserve_whitespace("\n\n" + signature);
    }
    
    private void set_cursor() {
        if (top_posting)
            body_html = CURSOR + body_html;
        else
            body_html = body_html + CURSOR;
    }
    
    private bool can_save() {
        return draft_manager != null
            && draft_manager.is_open
            && editor.can_undo()
            && account.information.save_drafts;
    }

    public CloseStatus should_close() {
        bool try_to_save = can_save();
        
        container.present();
        AlertDialog dialog;
        
        if (try_to_save) {
            dialog = new TernaryConfirmationDialog(container.top_window,
                _("Do you want to discard this message?"), null, Stock._KEEP, Stock._DISCARD,
                Gtk.ResponseType.CLOSE);
        } else {
            dialog = new ConfirmationDialog(container.top_window,
                _("Do you want to discard this message?"), null, Stock._DISCARD);
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
    
    private void on_close() {
        if (should_close() == CloseStatus.DO_CLOSE)
            container.close_container();
    }
    
    private void on_detach() {
        if (parent is ComposerEmbed)
            ((ComposerEmbed) parent).on_detach();
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
        filtered += Util.DOM.get_text_representation(editor.get_dom_document(), "blockquote");
        
        Regex url_regex = null;
        try {
            // Prepare to ignore urls later
            url_regex = new Regex(URL_REGEX, RegexCompileFlags.CASELESS);
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
        bool has_attachment = attachment_files.size > 0;
        bool has_body_or_attachment = has_body || has_attachment;
        
        string? confirmation = null;
        if (!has_subject && !has_body_or_attachment) {
            confirmation = _("Send message with an empty subject and body?");
        } else if (!has_subject) {
            confirmation = _("Send message with an empty subject?");
        } else if (!has_body_or_attachment) {
            confirmation = _("Send message with an empty body?");
        } else if (!has_attachment && email_contains_attachment_keywords()) {
            confirmation = _("Send message without an attachment?");
        }
        if (confirmation != null) {
            ConfirmationDialog dialog = new ConfirmationDialog(container.top_window,
                confirmation, null, Stock._OK);
            if (dialog.run() != Gtk.ResponseType.OK)
                return false;
        }
        return true;
    }
    
    // Sends the current message.
    private void on_send() {
        if (should_send())
            on_send_async.begin();
    }
    
    // Used internally by on_send()
    private async void on_send_async() {
        container.vanish();
        
        linkify_document(editor.get_dom_document());
        
        // Perform send.
        try {
            yield account.send_email_async(get_composed_email());
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
        container.close_container();
    }
    
    private void on_draft_state_changed() {
        switch (draft_manager.draft_state) {
            case Geary.App.DraftManager.DraftState.STORED:
                draft_save_text = DRAFT_SAVED_TEXT;
            break;
            
            case Geary.App.DraftManager.DraftState.STORING:
                draft_save_text = DRAFT_SAVING_TEXT;
            break;
            
            case Geary.App.DraftManager.DraftState.NOT_STORED:
                draft_save_text = "";
            break;
            
            case Geary.App.DraftManager.DraftState.ERROR:
                draft_save_text = DRAFT_ERROR_TEXT;
            break;
            
            default:
                assert_not_reached();
        }
    }
    
    private void on_draft_manager_fatal(Error err) {
        draft_save_text = DRAFT_ERROR_TEXT;
    }
    
    private void connect_to_draft_manager() {
        draft_manager.notify[Geary.App.DraftManager.PROP_DRAFT_STATE].connect(on_draft_state_changed);
        draft_manager.fatal.connect(on_draft_manager_fatal);
    }
    
    // This code is in a separate method due to https://bugzilla.gnome.org/show_bug.cgi?id=742621
    // connect_to_draft_manager() is simply for symmetry.  When above bug is fixed, this code can
    // be moved back into open/close methods
    private void disconnect_from_draft_manager() {
        draft_manager.notify[Geary.App.DraftManager.PROP_DRAFT_STATE].disconnect(on_draft_state_changed);
        draft_manager.fatal.disconnect(on_draft_manager_fatal);
    }
    
    // Returns the drafts folder for the current From account.
    private async void open_draft_manager_async(Cancellable? cancellable) throws Error {
        yield close_draft_manager_async(cancellable);
        
        if (!account.information.save_drafts)
            return;
        
        draft_manager = new Geary.App.DraftManager(account);
        try {
            yield draft_manager.open_async(editing_draft_id, cancellable);
        } catch (Error err) {
            debug("Unable to open draft manager %s: %s", draft_manager.to_string(), err.message);
            
            draft_manager = null;
            
            throw err;
        }
        
        // clear now, as it was only needed to open draft manager
        editing_draft_id = null;
        
        connect_to_draft_manager();
    }
    
    private async void close_draft_manager_async(Cancellable? cancellable) throws Error {
        // clear status text
        draft_save_text = "";
        
        // only clear editing_draft_id if associated with prior draft_manager, not due to this
        // widget being initialized with it
        if (draft_manager == null)
            return;
        
        disconnect_from_draft_manager();
        
        // drop ref even if close failed
        try {
            yield draft_manager.close_async(cancellable);
        } finally {
            draft_manager = null;
            editing_draft_id = null;
        }
    }
    
    // Resets the draft save timeout.
    private void reset_draft_timer() {
        draft_save_text = "";
        cancel_draft_timer();
        
        if (can_save())
            draft_save_timeout_id = Timeout.add_seconds(DRAFT_TIMEOUT_SEC, on_save_draft_timeout);
    }
    
    // Cancels the draft save timeout
    private void cancel_draft_timer() {
        if (draft_save_timeout_id == 0)
            return;
        
        Source.remove(draft_save_timeout_id);
        draft_save_timeout_id = 0;
    }
    
    private bool on_save_draft_timeout() {
        // this is not rescheduled by the event loop, so kill the timeout id
        draft_save_timeout_id = 0;
        
        save_draft();
        
        return false;
    }
    
    // Note that drafts are NOT "linkified."
    private Geary.Nonblocking.Semaphore? save_draft() {
        // cancel timer in favor of just doing it now
        cancel_draft_timer();
        
        try {
            if (draft_manager != null) {
                return draft_manager.update(get_composed_email(null, true).to_rfc822_message(),
                    draft_flags, null);
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
            if (draft_manager != null)
                return draft_manager.discard();
        } catch (Error err) {
            GLib.message("Unable to discard draft: %s", err.message);
        }
        
        return null;
    }
    
    // Used while waiting for draft to save before closing widget.
    private void make_gui_insensitive() {
        container.vanish();
        cancel_draft_timer();
    }
    
    private async void save_and_exit_async() {
        make_gui_insensitive();
        
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
        
        discard_draft();
        if (draft_manager != null)
            draft_manager.discard_on_close = true;
        try {
            yield close_draft_manager_async(null);
        } catch (Error err) {
            // ignored
        }
        
        container.close_container();
    }
    
    private void on_add_attachment_button_clicked() {
        AttachmentDialog dialog = null;
        do {
            // Transient parent of AttachmentDialog is this ComposerWindow
            // But this generates the following warning:
            // Attempting to add a widget with type AttachmentDialog to a
            // ComposerWindow, but as a GtkBin subclass a ComposerWindow can
            // only contain one widget at a time;
            // it already contains a widget of type GtkBox
            dialog = new AttachmentDialog(container.top_window);
        } while (!dialog.is_finished(add_attachment));
    }
    
    private void on_pending_attachments_button_clicked() {
        add_attachments(pending_attachments, false);
    }
    
    private void check_pending_attachments() {
        if (pending_attachments != null) {
            foreach (Geary.Attachment attachment in pending_attachments) {
                if (!attachment_files.contains(attachment.file)) {
                    header.show_pending_attachments = true;
                    return;
                }
            }
        }
        header.show_pending_attachments = false;
    }
    
    private void attachment_failed(string msg) {
        ErrorDialog dialog = new ErrorDialog(container.top_window, _("Cannot add attachment"), msg);
        dialog.run();
    }
    
    private bool add_attachment(File attachment_file, bool alert_errors = true) {
        FileInfo attachment_file_info;
        try {
            attachment_file_info = attachment_file.query_info("standard::size,standard::type",
                FileQueryInfoFlags.NONE);
        } catch(Error e) {
            if (alert_errors)
                attachment_failed(_("\"%s\" could not be found.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        if (attachment_file_info.get_file_type() == FileType.DIRECTORY) {
            if (alert_errors)
                attachment_failed(_("\"%s\" is a folder.").printf(attachment_file.get_path()));
            
            return false;
        }

        if (attachment_file_info.get_size() == 0){
            if (alert_errors)
                attachment_failed(_("\"%s\" is an empty file.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        try {
            FileInputStream? stream = attachment_file.read();
            if (stream != null)
                stream.close();
        } catch(Error e) {
            debug("File '%s' could not be opened for reading. Error: %s", attachment_file.get_path(),
                e.message);
            
            if (alert_errors)
                attachment_failed(_("\"%s\" could not be opened for reading.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        if (!attachment_files.add(attachment_file)) {
            if (alert_errors)
                attachment_failed(_("\"%s\" already attached for delivery.").printf(attachment_file.get_path()));
            
            return false;
        }
        
        Gtk.Box box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        attachments_box.pack_start(box);
        
        /// In the composer, the filename followed by its filesize, i.e. "notes.txt (1.12KB)"
        string label_text = _("%s (%s)").printf(attachment_file.get_basename(),
            Files.get_filesize_as_string(attachment_file_info.get_size()));
        Gtk.Label label = new Gtk.Label(label_text);
        box.pack_start(label);
        label.halign = Gtk.Align.START;
        label.xpad = 4;
        
        Gtk.Button remove_button = new Gtk.Button.with_mnemonic(Stock._REMOVE);
        box.pack_start(remove_button, false, false);
        remove_button.clicked.connect(() => remove_attachment(attachment_file, box));
        
        show_attachments();
        
        return true;
    }
    
    private void add_attachments(Gee.List<Geary.Attachment> attachments, bool alert_errors = true) {
        foreach(Geary.Attachment attachment in attachments)
            add_attachment(attachment.file, alert_errors);
    }
    
    private void remove_attachment(File file, Gtk.Box box) {
        if (!attachment_files.remove(file))
            return;
        
        foreach (weak Gtk.Widget child in attachments_box.get_children()) {
            if (child == box) {
                attachments_box.remove(box);
                break;
            }
        }
        
        show_attachments();
    }
    
    private void show_attachments() {
        if (attachment_files.size > 0 ) {
            attachments_box.show_all();
        } else {
            attachments_box.hide();
        }
        check_pending_attachments();
    }
    
    private void on_subject_changed() {
        reset_draft_timer();
    }
    
    private void validate_send_button() {
        header.send_enabled =
            to_entry.valid_or_empty && cc_entry.valid_or_empty && bcc_entry.valid_or_empty
            && (!to_entry.empty || !cc_entry.empty || !bcc_entry.empty);
        if (state == ComposerState.INLINE_COMPACT) {
            bool tocc = !to_entry.empty && !cc_entry.empty,
                ccbcc = !(to_entry.empty && cc_entry.empty) && !bcc_entry.empty;
            string label = to_entry.buffer.text + (tocc ? ", " : "")
                + cc_entry.buffer.text + (ccbcc ? ", " : "") + bcc_entry.buffer.text;
            StringBuilder tooltip = new StringBuilder();
            if (to_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in to_entry.addresses)
                    tooltip.append(_("To: ") + addr.get_full_address() + "\n");
            if (cc_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in cc_entry.addresses)
                    tooltip.append(_("Cc: ") + addr.get_full_address() + "\n");
            if (bcc_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in bcc_entry.addresses)
                    tooltip.append(_("Bcc: ") + addr.get_full_address() + "\n");
            if (reply_to_entry.addresses != null)
                foreach(Geary.RFC822.MailboxAddress addr in reply_to_entry.addresses)
                    tooltip.append(_("Reply-To: ") + addr.get_full_address() + "\n");
            header.set_recipients(label, tooltip.str.slice(0, -1));  // Remove trailing \n
        }
        
        reset_draft_timer();
    }
    
    private void on_formatting_action(Gtk.Action action) {
        if (compose_as_html)
            on_action(action);
    }
    
    private void on_action(Gtk.Action action) {
        if (action_flag)
            return;
        
        action_flag = true; // prevents recursion
        editor.get_dom_document().exec_command(action.get_name(), false, "");
        action_flag = false;
    }
    
    private void on_cut() {
        if (container.get_focus() == editor)
            editor.cut_clipboard();
        else if (container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) container.get_focus()).cut_clipboard();
    }
    
    private void on_copy() {
        if (container.get_focus() == editor)
            editor.copy_clipboard();
        else if (container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) container.get_focus()).copy_clipboard();
    }
    
    private void on_copy_link() {
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        c.set_text(hover_url, -1);
        c.store();
    }
    
    private WebKit.DOM.Node? get_left_text(WebKit.DOM.Node node, long offset) {
        WebKit.DOM.Document document = editor.get_dom_document();
        string node_value = node.node_value;

        // Offset is in unicode characters, but index is in bytes. We need to get the corresponding
        // byte index for the given offset.
        int char_count = node_value.char_count();
        int index = offset > char_count ? node_value.length : node_value.index_of_nth_char(offset);

        return offset > 0 ? document.create_text_node(node_value[0:index]) : null;
    }
    
    private void on_clipboard_text_received(Gtk.Clipboard clipboard, string? text) {
        if (text == null)
            return;
        
        // Insert plain text from clipboard.
        WebKit.DOM.Document document = editor.get_dom_document();
        document.exec_command("inserttext", false, text);
    
        // The inserttext command will not scroll if needed, but we can't use the clipboard
        // for plain text. WebKit allows us to scroll a node into view, but not an arbitrary
        // position within a text node. So we add a placeholder node at the cursor position,
        // scroll to that, then remove the placeholder node.
        try {
            WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
            WebKit.DOM.Node selection_base_node = selection.get_base_node();
            long selection_base_offset = selection.get_base_offset();
            
            WebKit.DOM.NodeList selection_child_nodes = selection_base_node.get_child_nodes();
            WebKit.DOM.Node ref_child = selection_child_nodes.item(selection_base_offset);
        
            WebKit.DOM.Element placeholder = document.create_element("SPAN");
            WebKit.DOM.Text placeholder_text = document.create_text_node("placeholder");
            placeholder.append_child(placeholder_text);
            
            if (selection_base_node.node_name == "#text") {
                WebKit.DOM.Node? left = get_left_text(selection_base_node, selection_base_offset);
                
                WebKit.DOM.Node parent = selection_base_node.parent_node;
                if (left != null)
                    parent.insert_before(left, selection_base_node);
                parent.insert_before(placeholder, selection_base_node);
                parent.remove_child(selection_base_node);
                
                placeholder.scroll_into_view_if_needed(false);
                parent.insert_before(selection_base_node, placeholder);
                if (left != null)
                    parent.remove_child(left);
                parent.remove_child(placeholder);
                selection.set_base_and_extent(selection_base_node, selection_base_offset, selection_base_node, selection_base_offset);
            } else {
                selection_base_node.insert_before(placeholder, ref_child);
                placeholder.scroll_into_view_if_needed(false);
                selection_base_node.remove_child(placeholder);
            }
            
        } catch (Error err) {
            debug("Error scrolling pasted text into view: %s", err.message);
        }
    }
    
    private void on_paste() {
        if (container.get_focus() == editor)
            get_clipboard(Gdk.SELECTION_CLIPBOARD).request_text(on_clipboard_text_received);
        else if (container.get_focus() is Gtk.Editable)
            ((Gtk.Editable) container.get_focus()).paste_clipboard();
    }
    
    private void on_paste_with_formatting() {
        if (container.get_focus() == editor)
            editor.paste_clipboard();
    }
    
    private void on_select_all() {
        editor.select_all();
    }
    
    private void on_remove_format() {
        editor.get_dom_document().exec_command("removeformat", false, "");
        editor.get_dom_document().exec_command("removeparaformat", false, "");
        editor.get_dom_document().exec_command("unlink", false, "");
        editor.get_dom_document().exec_command("backcolor", false, "#ffffff");
        editor.get_dom_document().exec_command("forecolor", false, "#000000");
    }
    
    private void on_compose_as_html() {
        WebKit.DOM.DOMTokenList body_classes = editor.get_dom_document().body.get_class_list();
        if (!compose_as_html) {
            toggle_toolbar_buttons(false);
            build_plaintext_menu();
            try {
                body_classes.add("plain");
            } catch (Error error) {
                debug("Error setting composer style: %s", error.message);
            }
        } else {
            toggle_toolbar_buttons(true);
            build_html_menu();
            try {
                body_classes.remove("plain");
            } catch (Error error) {
                debug("Error setting composer style: %s", error.message);
            }
        }
        GearyApplication.instance.config.compose_as_html = compose_as_html;
    }

    private void on_show_extended() {
        if (!show_extended) {
            bcc_label.visible = bcc_entry.visible = reply_to_label.visible = reply_to_entry.visible = false;
        } else {
            if (state == ComposerState.INLINE_COMPACT)
                state = ComposerState.INLINE;
            bcc_label.visible = bcc_entry.visible = reply_to_label.visible = reply_to_entry.visible = true;
        }
    }
    
    private void toggle_toolbar_buttons(bool show) {
        actions.get_action(ACTION_BOLD).visible =
            actions.get_action(ACTION_ITALIC).visible =
            actions.get_action(ACTION_UNDERLINE).visible =
            actions.get_action(ACTION_STRIKETHROUGH).visible =
            actions.get_action(ACTION_INSERT_LINK).visible =
            actions.get_action(ACTION_REMOVE_FORMAT).visible = show;
    }
    
    private void build_plaintext_menu() {
        GtkUtil.clear_menu(menu);
        
        menu.append(html_item2);

        menu.append(new Gtk.SeparatorMenuItem());
        menu.append(extended_item);
        menu.show_all();
    }
    
    private void build_html_menu() {
        GtkUtil.clear_menu(menu);
        
        menu.append(font_sans);
        menu.append(font_serif);
        menu.append(font_monospace);
        menu.append(new Gtk.SeparatorMenuItem());
        
        menu.append(font_small);
        menu.append(font_medium);
        menu.append(font_large);
        menu.append(new Gtk.SeparatorMenuItem());
        
        menu.append(color_item);
        menu.append(new Gtk.SeparatorMenuItem());
        
        menu.append(html_item);

        menu.append(new Gtk.SeparatorMenuItem());
        menu.append(extended_item);
        menu.show_all(); // Call this or only menu items associated with actions will be displayed.
    }
    
    private void on_font_sans() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontname", false, "sans");
    }
    
    private void on_font_serif() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontname", false, "serif");
    }
    
    private void on_font_monospace() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontname", false, "monospace");
    }
    
    private void on_font_size_small() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontsize", false, "1");
    }
    
    private void on_font_size_medium() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontsize", false, "3");
    }
    
    private void on_font_size_large() {
        if (!action_flag)
            editor.get_dom_document().exec_command("fontsize", false, "7");
    }
    
    private void on_select_color() {
        if (compose_as_html) {
            Gtk.ColorChooserDialog dialog = new Gtk.ColorChooserDialog(_("Select Color"),
                container.top_window);
            if (dialog.run() == Gtk.ResponseType.OK)
                editor.get_dom_document().exec_command("forecolor", false, dialog.get_rgba().to_string());
            
            dialog.destroy();
        }
    }
    
    private void on_indent(Gtk.Action action) {
        on_action(action);
        
        // Undo styling of blockquotes
        try {
            WebKit.DOM.NodeList node_list = editor.get_dom_document().query_selector_all(
                "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]");
            for (int i = 0; i < node_list.length; ++i) {
                WebKit.DOM.Element element = (WebKit.DOM.Element) node_list.item(i);
                element.remove_attribute("style");
                element.set_attribute("type", "cite");
            }
        } catch (Error error) {
            debug("Error removing blockquote style: %s", error.message);
        }
    }
    
    private void protect_blockquote_styles() {
        // We will search for an remove a particular styling when we quote text.  If that style
        // exists in the quoted text, we alter it slightly so we don't mess with it later.
        try {
            WebKit.DOM.NodeList node_list = editor.get_dom_document().query_selector_all(
                "blockquote[style=\"margin: 0 0 0 40px; border: none; padding: 0px;\"]");
            for (int i = 0; i < node_list.length; ++i) {
                ((WebKit.DOM.Element) node_list.item(i)).set_attribute("style", 
                    "margin: 0 0 0 40px; padding: 0px; border:none;");
            }
        } catch (Error error) {
            debug("Error protecting blockquotes: %s", error.message);
        }
    }
    
    private void on_insert_link() {
        if (compose_as_html)
            link_dialog("http://");
    }
    
    private static void on_link_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ComposerWidget composer) {
        try {
            composer.editor.get_dom_document().get_default_view().get_selection().
                select_all_children(element);
        } catch (Error e) {
            debug("Error selecting link: %s", e.message);
        }
    }
    
    private void link_dialog(string link) {
        Gtk.Dialog dialog = new Gtk.Dialog();
        bool existing_link = false;
        
        // Save information needed to re-establish selection
        WebKit.DOM.DOMSelection selection = editor.get_dom_document().get_default_view().
            get_selection();
        WebKit.DOM.Node anchor_node = selection.anchor_node;
        long anchor_offset = selection.anchor_offset;
        WebKit.DOM.Node focus_node = selection.focus_node;
        long focus_offset = selection.focus_offset;
        
        // Allow user to remove link if they're editing an existing one.
        if (focus_node != null && (focus_node is WebKit.DOM.HTMLAnchorElement ||
            focus_node.get_parent_element() is WebKit.DOM.HTMLAnchorElement)) {
            existing_link = true;
            dialog.add_buttons(Stock._REMOVE, Gtk.ResponseType.REJECT);
        }
        
        dialog.add_buttons(Stock._CANCEL, Gtk.ResponseType.CANCEL, Stock._OK,
            Gtk.ResponseType.OK);
        
        Gtk.Entry entry = new Gtk.Entry();
        entry.changed.connect(() => {
            // Only allow OK when there's text in the box.
            dialog.set_response_sensitive(Gtk.ResponseType.OK, 
                !Geary.String.is_empty(entry.text.strip()));
        });
        
        dialog.width_request = 350;
        dialog.get_content_area().spacing = 7;
        dialog.get_content_area().border_width = 10;
        dialog.get_content_area().pack_start(new Gtk.Label("Link URL:"));
        dialog.get_content_area().pack_start(entry);
        dialog.get_widget_for_response(Gtk.ResponseType.OK).can_default = true;
        dialog.set_default_response(Gtk.ResponseType.OK);
        dialog.show_all();
        
        entry.set_text(link);
        entry.activates_default = true;
        entry.move_cursor(Gtk.MovementStep.BUFFER_ENDS, 0, false);
        
        int response = dialog.run();
        
        // Re-establish selection, since selecting text in the Entry will de-select all
        // in the WebView.
        try {
            selection.set_base_and_extent(anchor_node, anchor_offset, focus_node, focus_offset);
        } catch (Error e) {
            debug("Error re-establishing selection: %s", e.message);
        }
        
        if (response == Gtk.ResponseType.OK)
            editor.get_dom_document().exec_command("createLink", false, entry.text);
        else if (response == Gtk.ResponseType.REJECT)
            editor.get_dom_document().exec_command("unlink", false, "");
        
        dialog.destroy();
        
        // Re-bind to anchor links.  This must be done every time link have changed.
        bind_event(editor,"a", "click", (Callback) on_link_clicked, this);
    }
    
    private string get_html() {
        return ((WebKit.DOM.HTMLElement) editor.get_dom_document().get_element_by_id(BODY_ID))
            .get_inner_html();
    }
    
    private string get_text() {
        return html_to_flowed_text((WebKit.DOM.HTMLElement) editor.get_dom_document()
            .get_element_by_id(BODY_ID));
    }
    
    private bool on_navigation_policy_decision_requested(WebKit.WebFrame frame,
        WebKit.NetworkRequest request, WebKit.WebNavigationAction navigation_action,
        WebKit.WebPolicyDecision policy_decision) {
        policy_decision.ignore();
        if (compose_as_html)
            link_dialog(request.uri);
        return true;
    }
    
    private void on_hovering_over_link(string? title, string? url) {
        if (compose_as_html) {
            message_overlay_label.label = url;
            hover_url = url;
            update_actions();
        }
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
    
    private void on_message_overlay_label_realize() {
        update_message_overlay_label_style();
    }
    
    private void on_message_overlay_label_style_changed() {
        update_message_overlay_label_style();
    }
    
    private void on_spell_check_changed() {
        editor.settings.enable_spell_checking = GearyApplication.instance.config.spell_check;
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
                    if (header.send_enabled)
                        on_send();
                    
                    return true;
                }
            break;
        }
        
        return base.key_press_event(event);
    }
    
    private bool on_context_menu(Gtk.Widget default_menu, WebKit.HitTestResult hit_test_result,
        bool keyboard_triggered) {
        Gtk.Menu context_menu = (Gtk.Menu) default_menu;
        Gtk.MenuItem? ignore_spelling = null, learn_spelling = null;
        bool suggestions = false;
        
        GLib.List<weak Gtk.Widget> children = context_menu.get_children();
        foreach (weak Gtk.Widget child in children) {
            Gtk.MenuItem item = (Gtk.MenuItem) child;
            if (item.is_sensitive()) {
                WebKit.ContextMenuAction action = WebKit.context_menu_item_get_action(item);
                if (action == WebKit.ContextMenuAction.SPELLING_GUESS) {
                    suggestions = true;
                    continue;
                }
                
                if (action == WebKit.ContextMenuAction.IGNORE_SPELLING)
                    ignore_spelling = item;
                else if (action == WebKit.ContextMenuAction.LEARN_SPELLING)
                    learn_spelling = item;
            }
            context_menu.remove(child);
        }
        
        if (suggestions)
            context_menu.append(new Gtk.SeparatorMenuItem());
        if (ignore_spelling != null)
            context_menu.append(ignore_spelling);
        if (learn_spelling != null)
            context_menu.append(learn_spelling);
        if (ignore_spelling != null || learn_spelling != null)
            context_menu.append(new Gtk.SeparatorMenuItem());
        
        // Undo
        Gtk.MenuItem undo = new Gtk.ImageMenuItem();
        undo.related_action = actions.get_action(ACTION_UNDO);
        context_menu.append(undo);
        
        // Redo
        Gtk.MenuItem redo = new Gtk.ImageMenuItem();
        redo.related_action = actions.get_action(ACTION_REDO);
        context_menu.append(redo);
        
        context_menu.append(new Gtk.SeparatorMenuItem());
        
        // Cut
        Gtk.MenuItem cut = new Gtk.ImageMenuItem();
        cut.related_action = actions.get_action(ACTION_CUT);
        context_menu.append(cut);
        
        // Copy
        Gtk.MenuItem copy = new Gtk.ImageMenuItem();
        copy.related_action = actions.get_action(ACTION_COPY);
        context_menu.append(copy);
        
        // Copy link.
        Gtk.MenuItem copy_link = new Gtk.ImageMenuItem();
        copy_link.related_action = actions.get_action(ACTION_COPY_LINK);
        context_menu.append(copy_link);
        
        // Paste
        Gtk.MenuItem paste = new Gtk.ImageMenuItem();
        paste.related_action = actions.get_action(ACTION_PASTE);
        context_menu.append(paste);
        
        // Paste with formatting
        if (compose_as_html) {
            Gtk.MenuItem paste_format = new Gtk.ImageMenuItem();
            paste_format.related_action = actions.get_action(ACTION_PASTE_FORMAT);
            context_menu.append(paste_format);
        }
        
        context_menu.append(new Gtk.SeparatorMenuItem());
        
        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(Stock.SELECT__ALL);
        select_all_item.activate.connect(on_select_all);
        context_menu.append(select_all_item);
        
        context_menu.show_all();
        
        update_actions();
        
        return false;
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
        
        WebKit.DOM.Document document = editor.get_dom_document();
        if (event.keyval == Gdk.Key.Tab) {
            document.exec_command("inserthtml", false,
                "<span style='white-space: pre-wrap'>\t</span>");
            return true;
        }
        
        if (event.keyval == Gdk.Key.ISO_Left_Tab) {
            // If there is no selection and the character before the cursor is tab, delete it.
            WebKit.DOM.DOMSelection selection = document.get_default_view().get_selection();
            if (selection.is_collapsed) {
                selection.modify("extend", "backward", "character");
                try {
                    if (selection.get_range_at(0).get_text() == "\t")
                        selection.delete_from_document();
                    else
                        selection.collapse_to_end();
                } catch (Error error) {
                    debug("Error handling Left Tab: %s", error.message);
                }
            }
            return true;
        }
        
        return false;
    }
    
    private void update_actions() {
        // Undo/redo.
        actions.get_action(ACTION_UNDO).sensitive = editor.can_undo();
        actions.get_action(ACTION_REDO).sensitive = editor.can_redo();
        
        // Clipboard.
        actions.get_action(ACTION_CUT).sensitive = editor.can_cut_clipboard();
        actions.get_action(ACTION_COPY).sensitive = editor.can_copy_clipboard();
        actions.get_action(ACTION_COPY_LINK).sensitive = hover_url != null;
        actions.get_action(ACTION_PASTE).sensitive = editor.can_paste_clipboard();
        actions.get_action(ACTION_PASTE_FORMAT).sensitive = editor.can_paste_clipboard() && compose_as_html;
        
        // Style toggle buttons.
        WebKit.DOM.DOMWindow window = editor.get_dom_document().get_default_view();
        actions.get_action(ACTION_REMOVE_FORMAT).sensitive = !window.get_selection().is_collapsed;
        
        WebKit.DOM.Element? active = window.get_selection().focus_node as WebKit.DOM.Element;
        if (active == null && window.get_selection().focus_node != null)
            active = window.get_selection().focus_node.get_parent_element();
        
        if (active != null && !action_flag) {
            action_flag = true;
            
            WebKit.DOM.CSSStyleDeclaration styles = window.get_computed_style(active, "");
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_BOLD)).active = 
                styles.get_property_value("font-weight") == "bold";
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_ITALIC)).active = 
                styles.get_property_value("font-style") == "italic";
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_UNDERLINE)).active = 
                styles.get_property_value("text-decoration") == "underline";
            
            ((Gtk.ToggleAction) actions.get_action(ACTION_STRIKETHROUGH)).active = 
                styles.get_property_value("text-decoration") == "line-through";
            
            // Font family.
            string font_name = styles.get_property_value("font-family").down();
            if (font_name.contains("sans-serif") ||
                font_name.contains("arial") ||
                font_name.contains("trebuchet") ||
                font_name.contains("helvetica"))
                font_sans.activate();
            else if (font_name.contains("serif") ||
                font_name.contains("georgia") ||
                font_name.contains("times"))
                font_serif.activate();
            else if (font_name.contains("monospace") ||
                font_name.contains("courier") ||
                font_name.contains("console"))
                font_monospace.activate();
            
            // Font size.
            int font_size;
            styles.get_property_value("font-size").scanf("%dpx", out font_size);
            if (font_size < 11)
                font_small.activate();
            else if (font_size > 20)
                font_large.activate();
            else
                font_medium.activate();
            
            action_flag = false;
        }
    }
    
    private void update_from_field() {
        from_single.visible = from_multiple.visible = from_label.visible = false;
        
        Gee.Map<string, Geary.AccountInformation> accounts;
        try {
            accounts = Geary.Engine.instance.get_accounts();
        } catch (Error e) {
            debug("Could not fetch account info: %s", e.message);
            
            return;
        }
        
        // Don't show in inline or compact modes.
        if (state == ComposerState.INLINE || state == ComposerState.INLINE_COMPACT)
            return;
        
        // If there's only one account, show nothing. (From fields are hidden above.)
        if (accounts.size <= 1)
            return;
        
        from_label.visible = true;
        
        if (compose_type == ComposeType.NEW_MESSAGE) {
            // For new messages, show the account combo-box.
            from_label.set_use_underline(true);
            from_label.set_mnemonic_widget(from_multiple);
            // Composer label (with mnemonic underscore) for the account selector
            // when choosing what address to send a message from.
            from_label.set_text_with_mnemonic(_("_From:"));
            
            from_multiple.visible = true;
            from_multiple.remove_all();
            foreach (Geary.AccountInformation a in accounts.values)
                from_multiple.append(a.email, a.get_mailbox_address().get_full_address());
            
            // Set the active account to the currently selected account, or failing that, set it
            // to the first account in the list.
            if (!from_multiple.set_active_id(account.information.email))
                from_multiple.set_active(0);
        } else {
            // For other types of messages, just show the from account.
            from_label.set_use_underline(false);
            // Composer label (without mnemonic underscore) for the account selector
            // when choosing what address to send a message from.
            from_label.set_text(_("From:"));
            
            from_single.label = account.information.get_mailbox_address().get_full_address();
            from_single.visible = true;
        }
    }
    
    private void on_from_changed() {
        if (compose_type != ComposeType.NEW_MESSAGE)
            return;
        
        bool changed = false;
        try {
            changed = update_from_account();
        } catch (Error err) {
            debug("Unable to update From: Account in composer: %s", err.message);
        }
        
        // if the Geary.Account didn't change and the drafts folder is open(ing), do nothing more;
        // need to check for the drafts folder because opening it in the case of multiple From:
        // is handled here alone, so need to open it if not already
        if (!changed && draft_manager != null)
            return;
        
        open_draft_manager_async.begin(null);
        reset_draft_timer();
    }
    
    private bool update_from_account() throws Error {
        // Since we've set the combo box ID to the email addresses, we can
        // fetch that and use it to grab the account from the engine.
        string? id = from_multiple.get_active_id();
        if (id == null)
            return false;
        
        // it's possible for changed signals to fire even though nothing has changed; catch that
        // here when possible to avoid a lot of extra work
        Geary.AccountInformation? new_account_info = Geary.Engine.instance.get_accounts().get(id);
        if (new_account_info == null)
            return false;
        
        Geary.Account new_account = Geary.Engine.instance.get_account_instance(new_account_info);
        if (new_account == account)
            return false;
        
        account = new_account;
        from = new_account_info.get_from().to_rfc822_string();
        set_entry_completions();
        
        return true;
    }
    
    private void set_entry_completions() {
        if (contact_list_store != null && contact_list_store.contact_store == account.get_contact_store())
            return;
        
        contact_list_store = new ContactListStore(account.get_contact_store());
        
        to_entry.completion = new ContactEntryCompletion(contact_list_store);
        cc_entry.completion = new ContactEntryCompletion(contact_list_store);
        bcc_entry.completion = new ContactEntryCompletion(contact_list_store);
        reply_to_entry.completion = new ContactEntryCompletion(contact_list_store);
    }
    
}

