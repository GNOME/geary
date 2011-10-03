/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Window for sending messages.
public class ComposerWindow : Gtk.Window {
    
    private Gtk.Entry to_entry;
    private Gtk.Entry cc_entry;
    private Gtk.Entry bcc_entry;
    private Gtk.Entry subject_entry;
    private Gtk.TextView message_text;
    
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
    
    public ComposerWindow() {
        Gtk.Builder builder = YorbaApplication.instance.create_builder("composer.glade");
        
        Gtk.Box box = builder.get_object("composer") as Gtk.Box;
        Gtk.Button send_button = builder.get_object("Send") as Gtk.Button;
        send_button.clicked.connect(on_send);
        
        to_entry = builder.get_object("to") as Gtk.Entry;
        cc_entry = builder.get_object("cc") as Gtk.Entry;
        bcc_entry = builder.get_object("bcc") as Gtk.Entry;
        subject_entry = builder.get_object("subject") as Gtk.Entry;
        message_text = builder.get_object("message") as Gtk.TextView;
        
        add(box);
    }
    
    public override void show_all() {
        set_default_size(400, 550);
        
        base.show_all();
    }
    
    private void on_send() {
        send(this);
    }
    
}
