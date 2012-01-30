/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Window for sending messages.
public class ComposerWindow : Gtk.Window {
    private static string DEFAULT_TITLE = _("New Message");
    
    private Gtk.Entry to_entry;
    private Gtk.Entry cc_entry;
    private Gtk.Entry bcc_entry;
    private Gtk.Entry subject_entry;
    private Gtk.SourceView message_text = new Gtk.SourceView();
    private Gtk.Button send_button;
    
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
        owned get { return message_text.buffer.text; }
        set { message_text.buffer.text = value; }
    }
    
    // Signal sent when the "Send" button is clicked.
    public signal void send(ComposerWindow composer);
    
    public ComposerWindow(Geary.ComposedEmail? prefill = null) {
        add_events(Gdk.EventMask.KEY_PRESS_MASK | Gdk.EventMask.KEY_RELEASE_MASK);
        Gtk.Builder builder = GearyApplication.instance.create_builder("composer.glade");
        
        Gtk.Box box = builder.get_object("composer") as Gtk.Box;
        send_button = builder.get_object("Send") as Gtk.Button;
        send_button.clicked.connect(on_send);
        
        to_entry = builder.get_object("to") as Gtk.Entry;
        cc_entry = builder.get_object("cc") as Gtk.Entry;
        bcc_entry = builder.get_object("bcc") as Gtk.Entry;
        subject_entry = builder.get_object("subject") as Gtk.Entry;
        Gtk.ScrolledWindow scroll = builder.get_object("scrolledwindow") as Gtk.ScrolledWindow;
        scroll.add(message_text);
        ((Gtk.SourceBuffer) message_text.buffer).highlight_matching_brackets = false;
        
        title = DEFAULT_TITLE;
        subject_entry.changed.connect(on_subject_changed);
        to_entry.changed.connect(validate_send_button);
        cc_entry.changed.connect(validate_send_button);
        bcc_entry.changed.connect(validate_send_button);
        
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
            if (prefill.body != null)
                message = prefill.body.buffer.to_utf8();
            
            if (!Geary.String.is_empty(to) && !Geary.String.is_empty(subject))
                message_text.grab_focus();
            else if (!Geary.String.is_empty(to))
                subject_entry.grab_focus();
        }
        
        add(box);
        validate_send_button();
        
        message_text.move_cursor(Gtk.MovementStep.BUFFER_ENDS, -1, false);
    }
    
    public Geary.ComposedEmail get_composed_email(
        Geary.RFC822.MailboxAddresses? default_from = null, DateTime? date_override = null) {
        Geary.ComposedEmail email = new Geary.ComposedEmail(
            date_override ?? new DateTime.now_local(),
            Geary.String.is_empty(from)
                ? default_from
                : new Geary.RFC822.MailboxAddresses.from_rfc822_string(from)
        );
        
        if (!Geary.String.is_empty(to))
            email.to = new Geary.RFC822.MailboxAddresses.from_rfc822_string(to);
        
        if (!Geary.String.is_empty(cc))
            email.cc = new Geary.RFC822.MailboxAddresses.from_rfc822_string(cc);
        
        if (!Geary.String.is_empty(bcc))
            email.bcc = new Geary.RFC822.MailboxAddresses.from_rfc822_string(bcc);
        
        if (!Geary.String.is_empty(in_reply_to))
            email.in_reply_to = new Geary.RFC822.MessageID(in_reply_to);
        
        if (!Geary.String.is_empty(references))
            email.references = new Geary.RFC822.MessageIDList.from_rfc822_string(references);
        
        if (!Geary.String.is_empty(subject))
            email.subject = new Geary.RFC822.Subject(subject);
        
        email.body = new Geary.RFC822.Text(new Geary.Memory.StringBuffer(message));
        
        return email;
    }
    
    public override void show_all() {
        set_default_size(650, 550);
        
        base.show_all();
    }
    
    private void on_send() {
        send(this);
    }
    
    private void on_subject_changed() {
        title = Geary.String.is_empty(subject_entry.text.strip()) ? DEFAULT_TITLE :
            subject_entry.text.strip();
    }
    
    private void validate_send_button() {
        send_button.sensitive = !Geary.String.is_empty(to_entry.get_text().strip()) ||
            !Geary.String.is_empty(cc_entry.get_text().strip()) ||
            !Geary.String.is_empty(bcc_entry.get_text().strip());
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
                this.destroy();
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

