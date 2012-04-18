/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Window for sending messages.
public class ComposerWindow : Gtk.Window {
    private static string DEFAULT_TITLE = _("New Message");
    
    private const string ACTION_UNDO = "undo";
    private const string ACTION_REDO = "redo";
    private const string ACTION_CUT = "cut";
    private const string ACTION_COPY = "copy";
    private const string ACTION_COPY_LINK = "copy link";
    private const string ACTION_PASTE = "paste";
    private const string ACTION_PASTE_FORMAT = "paste with formatting";
    private const string ACTION_BOLD = "bold";
    private const string ACTION_ITALIC = "italic";
    private const string ACTION_UNDERLINE = "underline";
    private const string ACTION_STRIKETHROUGH = "strikethrough";
    private const string ACTION_REMOVE_FORMAT = "removeformat";
    private const string ACTION_INDENT = "indent";
    private const string ACTION_OUTDENT = "outdent";
    private const string ACTION_JUSTIFY_LEFT = "justifyleft";
    private const string ACTION_JUSTIFY_RIGHT = "justifyright";
    private const string ACTION_JUSTIFY_CENTER = "justifycenter";
    private const string ACTION_JUSTIFY_FULL = "justifyfull";
    private const string ACTION_FONT = "font";
    private const string ACTION_COLOR = "color";
    private const string ACTION_INSERT_LINK = "insertlink";
    
    private const string REPLY_ID = "reply";
    private const string HTML_BODY = """
        <html><head><title></title>
        <style>
        body {
            margin: 10px !important;
            padding: 0 !important;
            background-color: white !important;
            font-size: 11pt !important;
        }
        blockquote {
            margin: 10px;
            padding: 5px;
            background-color: white;
            border: 0;
            border-left: 3px #aaa solid;
        }
        </style>
        </head><body id="reply" contenteditable="true"></body></html>""";
    
    // Signal sent when the "Send" button is clicked.
    public signal void send(ComposerWindow composer);
    
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
    
    public string in_reply_to { get; set; }
    public string references { get; set; }
    
    public string subject {
        get { return subject_entry.get_text(); }
        set { subject_entry.set_text(value); }
    }
    
    public string message {
        owned get { return get_html(); }
        set {
            reply_body = value;
            editor.load_string(HTML_BODY, "text/html", "UTF8", "");
        }
    }
    
    private string? reply_body = null;
    
    private EmailEntry to_entry;
    private EmailEntry cc_entry;
    private EmailEntry bcc_entry;
    private Gtk.Entry subject_entry;
    private Gtk.Button send_button;
    private Gtk.Label message_overlay_label;
    private Gtk.Menu? context_menu = null;
    private Gtk.ActionGroup actions;
    private string? hover_url = null;
    
    private WebKit.WebView editor;
    private Gtk.UIManager ui;
    
    public ComposerWindow(Geary.ComposedEmail? prefill = null) {
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK);
        Gtk.Builder builder = GearyApplication.instance.create_builder("composer.glade");
        
        Gtk.Box box = builder.get_object("composer") as Gtk.Box;
        send_button = builder.get_object("Send") as Gtk.Button;
        send_button.clicked.connect(on_send);
        
        to_entry = new EmailEntry();
        (builder.get_object("to") as Gtk.EventBox).add(to_entry);
        cc_entry = new EmailEntry();
        (builder.get_object("cc") as Gtk.EventBox).add(cc_entry);
        bcc_entry = new EmailEntry();
        (builder.get_object("bcc") as Gtk.EventBox).add(bcc_entry);
        subject_entry = builder.get_object("subject") as Gtk.Entry;
        Gtk.Alignment msg_area = builder.get_object("message area") as Gtk.Alignment;
        actions = builder.get_object("compose actions") as Gtk.ActionGroup;
        
        Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        Gtk.Overlay message_overlay = new Gtk.Overlay();
        message_overlay.add(scroll);
        msg_area.add(message_overlay);
        
        message_overlay_label = new Gtk.Label(null);
        message_overlay_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        message_overlay_label.halign = Gtk.Align.START;
        message_overlay_label.valign = Gtk.Align.END;
        message_overlay.add_overlay(message_overlay_label);
        
        title = DEFAULT_TITLE;
        subject_entry.changed.connect(on_subject_changed);
        to_entry.changed.connect(validate_send_button);
        cc_entry.changed.connect(validate_send_button);
        bcc_entry.changed.connect(validate_send_button);
        
        actions.get_action(ACTION_UNDO).activate.connect(on_action);
        actions.get_action(ACTION_REDO).activate.connect(on_action);
        
        actions.get_action(ACTION_CUT).activate.connect(on_cut);
        actions.get_action(ACTION_COPY).activate.connect(on_copy);
        actions.get_action(ACTION_COPY_LINK).activate.connect(on_copy_link);
        actions.get_action(ACTION_PASTE).activate.connect(on_paste);
        actions.get_action(ACTION_PASTE_FORMAT).activate.connect(on_paste_with_formatting);
        
        actions.get_action(ACTION_BOLD).activate.connect(on_action);
        actions.get_action(ACTION_ITALIC).activate.connect(on_action);
        actions.get_action(ACTION_UNDERLINE).activate.connect(on_action);
        actions.get_action(ACTION_STRIKETHROUGH).activate.connect(on_action);
        
        actions.get_action(ACTION_REMOVE_FORMAT).activate.connect(on_remove_format);
        
        actions.get_action(ACTION_INDENT).activate.connect(on_action);
        actions.get_action(ACTION_OUTDENT).activate.connect(on_action);
        
        actions.get_action(ACTION_JUSTIFY_LEFT).activate.connect(on_action);
        actions.get_action(ACTION_JUSTIFY_RIGHT).activate.connect(on_action);
        actions.get_action(ACTION_JUSTIFY_CENTER).activate.connect(on_action);
        actions.get_action(ACTION_JUSTIFY_FULL).activate.connect(on_action);
        
        actions.get_action(ACTION_FONT).activate.connect(on_select_font);
        actions.get_action(ACTION_COLOR).activate.connect(on_select_color);
        actions.get_action(ACTION_INSERT_LINK).activate.connect(on_insert_link);
        
        ui = new Gtk.UIManager();
        ui.insert_action_group(actions, 0);
        add_accel_group(ui.get_accel_group());
        GearyApplication.instance.load_ui_file_for_manager(ui, "composer_accelerators.ui");
        
        if (prefill != null) {
            if (prefill.from != null)
                from = prefill.from.to_rfc822_string();
            if (prefill.to != null)
                to = prefill.to.to_rfc822_string();
            if (prefill.cc != null)
                cc = prefill.cc.to_rfc822_string();
            if (prefill.bcc != null)
                bcc = prefill.bcc.to_rfc822_string();
            if (prefill.in_reply_to != null)
                in_reply_to = prefill.in_reply_to.value;
            if (prefill.references != null)
                references = prefill.references.to_rfc822_string();
            if (prefill.subject != null)
                subject = prefill.subject.value;
            if (prefill.body_html != null)
                reply_body = prefill.body_html.buffer.to_utf8();
            if (reply_body == null && prefill.body_text != null)
                reply_body = "<pre>" + prefill.body_text.buffer.to_utf8();
        }
        
        editor = new WebKit.WebView();
        editor.load_finished.connect(on_load_finished);
        editor.hovering_over_link.connect(on_hovering_over_link);
        editor.button_press_event.connect(on_button_press_event);
        editor.move_focus.connect(update_actions);
        editor.copy_clipboard.connect(update_actions);
        editor.cut_clipboard.connect(update_actions);
        editor.paste_clipboard.connect(update_actions);
        editor.undo.connect(update_actions);
        editor.redo.connect(update_actions);
        editor.selection_changed.connect(update_actions);
        editor.user_changed_contents.connect(update_actions);
        
        // only do this after setting reply_body
        editor.load_string(HTML_BODY, "text/html", "UTF8", "");
        
        editor.navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        editor.new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        
        GearyApplication.instance.config.spell_check_changed.connect(on_spell_check_changed);
        
        WebKit.WebSettings s = new WebKit.WebSettings();
        s.enable_spell_checking = GearyApplication.instance.config.spell_check;
        s.auto_load_images = false;
        s.enable_default_context_menu = true;
        s.enable_scripts = false;
        s.enable_java_applet = false;
        s.enable_plugins = false;
        s.enable_default_context_menu = false;
        editor.settings = s;
        
        scroll.add(editor);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        add(box);
        validate_send_button();
    }
    
    private void on_load_finished(WebKit.WebFrame frame) {
        if (reply_body == null)
            return;
        
        WebKit.DOM.HTMLElement? reply = editor.get_dom_document().get_element_by_id(
            REPLY_ID) as WebKit.DOM.HTMLElement;
        assert(reply != null);
        
        try {
            reply.set_inner_html("<br /><br />" + reply_body + "<br />");
        } catch (Error e) {
            debug("Failed to load email for reply: %s", e.message);
        }
        
        // Set focus.
        if (!Geary.String.is_empty(to) && !Geary.String.is_empty(subject)) {
            editor.grab_focus();
            reply.focus();
        } else if (!Geary.String.is_empty(to)) {
            subject_entry.grab_focus();
        }
        
        update_actions();
    }
    
    public Geary.ComposedEmail get_composed_email(
        Geary.RFC822.MailboxAddresses? default_from = null, DateTime? date_override = null) {
        Geary.ComposedEmail email = new Geary.ComposedEmail(
            date_override ?? new DateTime.now_local(),
            Geary.String.is_empty(from)
                ? default_from
                : new Geary.RFC822.MailboxAddresses.from_rfc822_string(from)
        );
        
        if (to_entry.addresses != null)
            email.to = to_entry.addresses;
        
        if (cc_entry.addresses != null)
            email.cc = cc_entry.addresses;
        
        if (bcc_entry.addresses != null)
            email.bcc = bcc_entry.addresses;
        
        if (!Geary.String.is_empty(in_reply_to))
            email.in_reply_to = new Geary.RFC822.MessageID(in_reply_to);
        
        if (!Geary.String.is_empty(references))
            email.references = new Geary.RFC822.MessageIDList.from_rfc822_string(references);
        
        if (!Geary.String.is_empty(subject))
            email.subject = new Geary.RFC822.Subject(subject);
        
        email.body_html = new Geary.RFC822.Text(new Geary.Memory.StringBuffer(get_html()));
        email.body_text = new Geary.RFC822.Text(new Geary.Memory.StringBuffer(get_text()));

        // User-Agent
        email.mailer = GearyApplication.PRGNAME + "/" + GearyApplication.VERSION;
        
        return email;
    }
    
    public override void show_all() {
        set_default_size(680, 600);
        
        base.show_all();
    }
    
    private bool should_close() {
        // TODO: Check if the message was (automatically) saved
        if (editor.can_undo()) {
            var dialog = new Gtk.MessageDialog(this, 0,
                Gtk.MessageType.WARNING, Gtk.ButtonsType.NONE,
                _("Do you want to discard the unsaved message?"));
            dialog.add_buttons(Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL,
                Gtk.Stock.DISCARD, Gtk.ResponseType.OK);
            dialog.set_default_response(Gtk.ResponseType.CANCEL);
            int response = dialog.run();
            dialog.destroy();
            
            if (response != Gtk.ResponseType.OK)
                return false;
        }
        return true;
    }
    
    public override bool delete_event(Gdk.EventAny event) {
        return !should_close();
    }
    
    private void on_send() {
        send(this);
    }
    
    private void on_subject_changed() {
        title = Geary.String.is_empty(subject_entry.text.strip()) ? DEFAULT_TITLE :
            subject_entry.text.strip();
    }
    
    private void validate_send_button() {
        send_button.sensitive =
            to_entry.valid_or_empty && cc_entry.valid_or_empty && bcc_entry.valid_or_empty
         && (!to_entry.empty || !cc_entry.empty || !bcc_entry.empty);
    }
    
    private void on_action(Gtk.Action action) {
        editor.get_dom_document().exec_command(action.get_name(), false, "");
    }
    
    private void on_cut() {
        if (get_focus() == editor)
            editor.cut_clipboard();
        else if (get_focus() is Gtk.Editable)
            ((Gtk.Editable) get_focus()).cut_clipboard();
    }
    
    private void on_copy() {
        if (get_focus() == editor)
            editor.copy_clipboard();
        else if (get_focus() is Gtk.Editable)
            ((Gtk.Editable) get_focus()).copy_clipboard();
    }
    
    private void on_copy_link() {
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        c.set_text(hover_url, -1);
        c.store();
    }
    
    private void on_clipboard_text_received(Gtk.Clipboard clipboard, string? text) {
        if (text == null)
            return;
        
        // Insert plain text from clipboard.
        editor.get_dom_document().exec_command("inserthtml", false, 
            Geary.HTML.newlines_to_br(Geary.HTML.escape_markup(text)));
    }
    
    private void on_paste() {
        if (get_focus() == editor)
            //editor.paste_clipboard();
            get_clipboard(Gdk.SELECTION_CLIPBOARD).request_text(on_clipboard_text_received);
        else if (get_focus() is Gtk.Editable)
            ((Gtk.Editable) get_focus()).paste_clipboard();
    }
    
    private void on_paste_with_formatting() {
        if (get_focus() == editor)
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
    
    private void on_select_font() {
        Gtk.FontChooserDialog dialog = new Gtk.FontChooserDialog("Select font", this);
        if (dialog.run() == Gtk.ResponseType.OK) {
            editor.get_dom_document().exec_command("fontname", false, dialog.get_font_family().
                get_name());
            editor.get_dom_document().exec_command("fontsize", false,
                (((double) dialog.get_font_size()) / 4000.0).to_string());
        }
        
        dialog.destroy();
    }
    
    private void on_select_color() {
        Gtk.ColorSelectionDialog dialog = new Gtk.ColorSelectionDialog("Select Color");
        if (dialog.run() == Gtk.ResponseType.OK) {
            string color = ((Gtk.ColorSelection) dialog.get_color_selection()).
                current_rgba.to_string();
            
            editor.get_dom_document().exec_command("forecolor", false, color);
        }
        
        dialog.destroy();
    }
    
    private void on_insert_link() {
        link_dialog("http://");
    }
    
    private void link_dialog(string link) {
        Gtk.Dialog dialog = new Gtk.Dialog.with_buttons("", this, 0,
            Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.OK, Gtk.ResponseType.OK);
        Gtk.Entry entry = new Gtk.Entry();
        dialog.get_content_area().pack_start(new Gtk.Label("Link URL:"));
        dialog.get_content_area().pack_start(entry);
        dialog.set_default_response(Gtk.ResponseType.OK);
        dialog.show_all();
        
        entry.set_text(link);
        
        if (dialog.run() == Gtk.ResponseType.OK) {
            if (!Geary.String.is_empty(entry.text.strip()))
                editor.get_dom_document().exec_command("createLink", false, entry.text);
            else
                editor.get_dom_document().exec_command("unlink", false, "");
        }
        
        dialog.destroy();
    }
    
    // Inserts a newline that's fully unindented.
    private void newline_unindented(Gdk.EventKey event) {
        
        bool inside_quote = false;
        int indent_level = 0;
        
        WebKit.DOM.Node? active = editor.get_dom_document().get_default_view().get_selection().
            focus_node as WebKit.DOM.Node;
        if (active == null)
            return;
        
        // Count number of parent elements.
        while (active != null && !(active is WebKit.DOM.HTMLBodyElement)) {
            if (active is WebKit.DOM.HTMLQuoteElement)
                inside_quote = true;
            
            active = active.get_parent_node();
            indent_level++;
        }
        
        // Only un-indent automatically if we're inside a blockquote.
        if (inside_quote) {
            editor.get_dom_document().exec_command("insertlinebreak", false, "");
            editor.key_press_event(event);
            
            // Send an up key.
            event.keyval = Gdk.keyval_from_name("Up");
            Gdk.KeymapKey[] keys;
            Gdk.Keymap.get_default().get_entries_for_keyval(event.keyval, out keys);
            event.hardware_keycode = (uint16) keys[0].keycode;
            event.group = (uint8) keys[0].group;
            editor.key_press_event(event);
            
            for (int i = 0; i < indent_level; i++)
                editor.get_dom_document().exec_command("outdent", false, "");
        } else {
            editor.key_press_event(event);
        }
    }
    
    private string get_html() {
        return editor.get_dom_document().get_body().get_inner_html();
    }
    
    private string get_text() {
        return editor.get_dom_document().get_body().get_inner_text();
    }
    
    private bool on_navigation_policy_decision_requested(WebKit.WebFrame frame,
        WebKit.NetworkRequest request, WebKit.WebNavigationAction navigation_action,
        WebKit.WebPolicyDecision policy_decision) {
        policy_decision.ignore();
        link_dialog(request.uri);
        return true;
    }
    
    private void on_hovering_over_link(string? title, string? url) {
        message_overlay_label.label = url;
        hover_url = url;
        update_actions();
    }
    
    private void on_spell_check_changed() {
        editor.settings.enable_spell_checking = GearyApplication.instance.config.spell_check;
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Return":
            case "KP_Enter":
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 && send_button.sensitive)
                    on_send();
                else if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0 && 
                    get_focus() == editor)
                    newline_unindented(event);
                else
                    handled = false;
            break;
            
            case "Escape":
                if (should_close())
                    destroy();
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return base.key_press_event(event);
    }
    
    private bool on_button_press_event(Gdk.EventButton event) {
        if (event.button == 3)
            create_context_menu(event);
        
        return false;
    }
    
    private void create_context_menu(Gdk.EventButton event) {
        context_menu = new Gtk.Menu();
        
        // Undo
        Gtk.MenuItem undo = new Gtk.MenuItem();
        undo.related_action = actions.get_action(ACTION_UNDO);
        context_menu.append(undo);
        
        // Redo
        Gtk.MenuItem redo = new Gtk.MenuItem();
        redo.related_action = actions.get_action(ACTION_REDO);
        context_menu.append(redo);
        
        context_menu.append(new Gtk.MenuItem());
        
        // Cut
        Gtk.MenuItem cut = new Gtk.MenuItem();
        cut.related_action = actions.get_action(ACTION_CUT);
        context_menu.append(cut);
        
        // Copy
        Gtk.MenuItem copy = new Gtk.MenuItem();
        copy.related_action = actions.get_action(ACTION_COPY);
        context_menu.append(copy);
        
        // Copy link.
        Gtk.MenuItem copy_link = new Gtk.MenuItem();
        copy_link.related_action = actions.get_action(ACTION_COPY_LINK);
        context_menu.append(copy_link);
        
        // Paste
        Gtk.MenuItem paste = new Gtk.MenuItem();
        paste.related_action = actions.get_action(ACTION_PASTE);
        context_menu.append(paste);
        
        // Paste with formatting
        Gtk.MenuItem paste_format = new Gtk.MenuItem();
        paste_format.related_action = actions.get_action(ACTION_PASTE_FORMAT);
        context_menu.append(paste_format);
        
        context_menu.append(new Gtk.MenuItem());
        
        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(_("Select _All"));
        select_all_item.activate.connect(on_select_all);
        context_menu.append(select_all_item);
        
        context_menu.show_all();
        context_menu.popup(null, null, null, event.button, event.time);
    }
    
    private void update_actions() {
        actions.get_action(ACTION_UNDO).sensitive = editor.can_undo();
        actions.get_action(ACTION_REDO).sensitive = editor.can_redo();
        
        actions.get_action(ACTION_CUT).sensitive = editor.can_cut_clipboard();
        actions.get_action(ACTION_COPY).sensitive = editor.can_copy_clipboard();
        actions.get_action(ACTION_COPY_LINK).sensitive = hover_url != null;
        actions.get_action(ACTION_PASTE).sensitive = editor.can_paste_clipboard();
        actions.get_action(ACTION_PASTE_FORMAT).sensitive = editor.can_paste_clipboard();
    }
}

