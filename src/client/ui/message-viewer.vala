/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageViewer : Gtk.Viewport {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.PROPERTIES;
    
    private const int HEADER_COL_SPACING = 10;
    private const int HEADER_ROW_SPACING = 3;
    private const int MESSAGE_BOX_MARGIN = 10;
    
    // List of emails corresponding with VBox.
    public Gee.LinkedList<Geary.Email> messages { get; private set; default = 
        new Gee.LinkedList<Geary.Email>(); }
    
    // GUI containing message widgets.
    private Gtk.VBox message_box = new Gtk.VBox(false, 0);
    
    // Used for theme changes.
    private Gtk.TextView? sample_view = null;
    
    public MessageViewer() {
        valign = Gtk.Align.START;
        vexpand = true;
        add(message_box);
        set_border_width(0);
        message_box.set_border_width(0);
        message_box.spacing = 0;
    }
    
    // Removes all displayed e-mails from the view.
    public void clear() {
        messages.clear();
        
        foreach (Gtk.Widget w in message_box.get_children())
            message_box.remove(w);
    }
    
    private void add_style() {
        string style = """
            MessageViewer .separator {
                border-color: #cccccc;
                border-style: solid;
                border-width: 1;
                -GtkWidget-separator-height: 2;
            }
        """;
        
        try {
            Gtk.CssProvider p = new Gtk.CssProvider();
            p.load_from_data(style, -1);
             
            Gtk.StyleContext.add_provider_for_screen(GearyApplication.instance.get_main_window().
                get_screen(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION) ;
        } catch (Error err) {
            warning("Couldn't set style: %s", err.message);
        }
    }
    
    // Adds a message to the view.
    public void add_message(Geary.Email email) {
        messages.add(email);
        Gtk.Builder builder = GearyApplication.instance.create_builder("message.glade");
        debug("Message id: %s", email.id.to_string());
        
        string username;
        try {
            // TODO: Multiple accounts.
            username = Geary.Engine.get_usernames(GearyApplication.instance.
                get_user_data_directory()).get(0);
        } catch (Error e) {
            error("Unable to get username. Error: %s", e.message);
        }
        
        // Only include to string if it's not just this account.
        // TODO: multiple accounts.
        string to = "";
        if (email.to != null) {
            if (!(email.to.get_all().size == 1 && email.to.get_all().get(0).address == username))
                to = email.to.to_string();
        }
        
        Gtk.Box container = builder.get_object("mail container") as Gtk.Box;
        Gtk.Grid header = builder.get_object("header") as Gtk.Grid;
        Gtk.Alignment icon_area = builder.get_object("icon area") as Gtk.Alignment;
        Gtk.TextView body = builder.get_object("body") as Gtk.TextView;
        if (sample_view == null)
            sample_view = body;
        body.style_updated.connect(on_text_style_changed);
        body.key_press_event.connect(on_key_press_event);
        body.key_release_event.connect(on_key_release_event);
        on_text_style_changed();
        
        header.column_spacing = HEADER_COL_SPACING;
        header.row_spacing = HEADER_ROW_SPACING;
        
        if (email.properties.email_flags.is_unread())
            icon_area.add(new Gtk.Image.from_pixbuf(IconFactory.instance.unread));
        
        int header_height = 0;
        if (email.from != null)
            insert_header(header, header_height++, _("From:"), email.from.to_string(), true);
        
        insert_header(header, header_height++, _("To:"), to);
        
        if (email.cc != null)
            insert_header(header, header_height++, _("Cc:"), email.cc.to_string());
            
        if (email.subject != null)
            insert_header(header, header_height++, _("Subject:"), email.subject.value);
            
        if (email.date != null)
         insert_header(header, header_height++, _("Date:"), Date.pretty_print_verbose(email.date.value));
        
        try {
            body.buffer.text = email.get_message().get_first_mime_part_of_content_type("text/plain").
                to_utf8();
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }
        
        BackgroundBox box = new BackgroundBox();
        box.add(container);
        box.margin = MESSAGE_BOX_MARGIN;
        
        message_box.pack_end(box, false, false);
        message_box.show_all();
        
        add_style();
    }
    
    // Inserts a header field (to, from, subject, etc.)
    private void insert_header(Gtk.Grid header, int header_height, string _title, string? _value, 
        bool bold = false) {
        if (Geary.String.is_empty(_value))
            return;
        
        string title = Geary.String.escape_markup(_title);
        string value = Geary.String.escape_markup(_value);
        
        Gtk.Label label_title = new Gtk.Label(null);
        Gtk.Label label_value = new Gtk.Label(null);
        
        label_title.set_line_wrap(true);
        label_value.set_line_wrap(true);
        label_title.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR);
        label_value.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR);
        label_title.set_alignment(1.0f, 0.0f);
        label_value.set_alignment(0.0f, 0.0f);
        label_title.selectable = true;
        label_value.selectable = true;
        
        label_title.set_markup("<span color='#aaaaaa' size='smaller'>%s</span>".printf(title));
        if (bold)
            label_value.set_markup("<span size='smaller' weight='bold'>%s</span>".printf(value));
        else
            label_value.set_markup("<span size='smaller'>%s</span>".printf(value));
        
        label_title.show();
        label_value.show();
        
        header.attach(label_title, 0, header_height, 1, 1);
        header.attach(label_value, 1, header_height, 1, 1);
    }
    
    // Makes the background match the TextView background.
    private void on_text_style_changed() {
        if (sample_view == null)
            return;
        
        Gdk.RGBA color = Gdk.RGBA();
        color.parse(sample_view.style.base[0].to_string());
        foreach (Gtk.Widget w in message_box.get_children())
            w.override_background_color(Gtk.StateFlags.NORMAL, color);
    }
    
    public override bool key_press_event(Gdk.EventKey event) {
        bool handled = true;
        
        switch (Gdk.keyval_name(event.keyval)) {
            case "Up":
            case "KP_Up":
            case "Down":
            case "KP_Down":
                // Add control mask to up an down keys.  This is a hack due
                // to a binding issue; see ticket #4387
                event.state |= Gdk.ModifierType.CONTROL_MASK;
                // Pass up to scrolled window.
                parent.key_press_event(event);
            break;
            
            case "Home":
            case "KP_Home":
            case "End":
            case "KP_End":
            case "Page_Down":
            case "KP_Page_Down":
            case "Page_Up":
            case "KP_Page_Up":
                // Pass up to scrolled window.
                parent.key_press_event(event);
            break;
            
            default:
                handled = false;
            break;
        }
        
        if (handled)
            return true;
        
        return (base.key_press_event != null) ? base.key_press_event(event) : true;
    }
    
    public override bool key_release_event(Gdk.EventKey event) {
        bool parent_ret = parent.key_release_event(event);
        if (parent_ret)
            return true;
        
        return (base.key_release_event != null) ? base.key_release_event(event) : true;
    }
    
    private bool on_key_press_event(Gdk.EventKey event) {
        return key_press_event(event);
    }
    
    private bool on_key_release_event(Gdk.EventKey event) {
        return key_release_event(event);
    }
}

