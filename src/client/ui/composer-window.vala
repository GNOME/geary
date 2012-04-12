/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Window for sending messages.
public class ComposerWindow : Gtk.Window {
    private static string DEFAULT_TITLE = _("New Message");
    
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
        </head><body>
        <p id="top"></p>
        <span id="reply"></span>
        </body></html>""";
    
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
        Gtk.ActionGroup actions = builder.get_object("compose actions") as Gtk.ActionGroup;
        
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
        
        actions.get_action("undo").activate.connect(on_action);
        actions.get_action("redo").activate.connect(on_action);
        
        actions.get_action("cut").activate.connect(on_cut);
        actions.get_action("copy").activate.connect(on_copy);
        actions.get_action("paste").activate.connect(on_paste);
        
        actions.get_action("bold").activate.connect(on_action);
        actions.get_action("italic").activate.connect(on_action);
        actions.get_action("underline").activate.connect(on_action);
        actions.get_action("strikethrough").activate.connect(on_action);
        
        actions.get_action("removeformat").activate.connect(on_remove_format);
        
        actions.get_action("indent").activate.connect(on_action);
        actions.get_action("outdent").activate.connect(on_action);
        
        actions.get_action("justifyleft").activate.connect(on_action);
        actions.get_action("justifyright").activate.connect(on_action);
        actions.get_action("justifycenter").activate.connect(on_action);
        actions.get_action("justifyfull").activate.connect(on_action);
        
        actions.get_action("font").activate.connect(on_select_font);
        actions.get_action("color").activate.connect(on_select_color);
        actions.get_action("insertlink").activate.connect(on_insert_link);
        
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
        editor.set_editable(true);
        editor.load_finished.connect(on_load_finished);
        editor.hovering_over_link.connect(on_hovering_over_link);
        editor.load_string(HTML_BODY, "text/html", "UTF8", ""); // only do this after setting reply_body
        
        if (!Geary.String.is_empty(to) && !Geary.String.is_empty(subject))
            editor.grab_focus();
        else if (!Geary.String.is_empty(to))
            subject_entry.grab_focus();
        
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
        editor.settings = s;
        
        scroll.add(editor);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        
        add(box);
        validate_send_button();
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
    
    private void on_paste() {
        if (get_focus() == editor)
            editor.paste_clipboard();
        else if (get_focus() is Gtk.Editable)
            ((Gtk.Editable) get_focus()).paste_clipboard();
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
    
    private string get_html() {
        return editor.get_dom_document().get_body().get_inner_html();
    }
    
    private string get_text() {
        return editor.get_dom_document().get_body().get_inner_text();
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
        } else if (!Geary.String.is_empty(to)) {
            subject_entry.grab_focus();
        }
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
}

