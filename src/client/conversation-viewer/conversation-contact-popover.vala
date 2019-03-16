/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Display contact information and supported actions for a contact.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-contact-popover.ui")]
public class Conversation.ContactPopover : Gtk.Popover {


    public Application.Contact contact { get; private set; }

    public Geary.RFC822.MailboxAddress mailbox { get; private set; }

    private GLib.Cancellable load_cancellable = new GLib.Cancellable();

    [GtkChild]
    private Gtk.Grid container;

    [GtkChild]
    private Gtk.Image avatar;

    [GtkChild]
    private Gtk.Label contact_name;

    [GtkChild]
    private Gtk.Label contact_address;


    public ContactPopover(Gtk.Widget relative_to,
                          Application.Contact contact,
                          Geary.RFC822.MailboxAddress mailbox) {
        this.relative_to = relative_to;
        this.contact = contact;
        this.mailbox = mailbox;

        contact.changed.connect(this.on_contact_changed);
        update();
    }

    public void add_section(GLib.MenuModel section,
                            Gee.Map<string,GLib.Variant> values) {
        Gtk.Separator separator = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
        separator.show();
        this.container.add(separator);
        for (int i = 0; i < section.get_n_items(); i++) {
            GLib.MenuItem item = new MenuItem.from_model(section, i);
            string action_fq = (string) item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );

            string action_name = action_fq.substring(action_fq.index_of(".") + 1);

            Gtk.ModelButton button = new Gtk.ModelButton();
            button.text = (string) item.get_attribute_value(
                Menu.ATTRIBUTE_LABEL, VariantType.STRING
            );
            button.action_name = (string) item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            button.action_target = values[action_name];
            button.show();

            this.container.add(button);
        }
    }

    /**
     * Starts loading the avatar for the message's sender.
     */
    public async void load_avatar() {
        MainWindow? main = this.get_toplevel() as MainWindow;
        if (main != null) {
            Application.AvatarStore loader = main.application.controller.avatars;
            int window_scale = get_scale_factor();
            int pixel_size = Application.AvatarStore.PIXEL_SIZE * window_scale;
            try {
                Gdk.Pixbuf? avatar_buf = yield loader.load(
                    this.mailbox,
                    pixel_size,
                    this.load_cancellable
                );
                if (avatar_buf != null) {
                    this.avatar.set_from_surface(
                        Gdk.cairo_surface_create_from_pixbuf(
                            avatar_buf, window_scale, get_window()
                        )
                    );
                }
            } catch (GLib.Error err) {
                debug("Conversation load failed: %s", err.message);
            }
        }
    }

    public override void destroy() {
        this.contact.changed.disconnect(this.on_contact_changed);
        this.load_cancellable.cancel();
        base.destroy();
    }

    private void update() {
        string display_name = this.contact.display_name;
        this.contact_name.set_text(display_name);

        if (!this.contact.display_name_is_email) {
            this.contact_address.set_text(this.mailbox.address);
        } else {
            this.contact_name.vexpand = true;
            this.contact_name.valign = FILL;
            this.contact_address.hide();
        }
    }

    private void on_contact_changed() {
        update();
    }

    [GtkCallback]
    private void after_closed() {
        GLib.Idle.add(() => {
                this.destroy();
                return GLib.Source.REMOVE;
            } );
    }

}
