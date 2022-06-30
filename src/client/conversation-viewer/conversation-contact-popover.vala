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


    private const string ACTION_COPY_EMAIL= "copy-email";
    private const string ACTION_LOAD_REMOTE = "load-remote";
    private const string ACTION_NEW_CONVERSATION = "new-conversation";
    private const string ACTION_OPEN = "open";
    private const string ACTION_SAVE = "save";
    private const string ACTION_SHOW_CONVERSATIONS = "show-conversations";
    private const string ACTION_STAR = "star";
    private const string ACTION_UNSTAR = "unstar";

    private const string ACTION_GROUP = "con";

    private const GLib.ActionEntry[] ACTION_ENTRIES = {
        {ACTION_COPY_EMAIL,         on_copy_email,                },
        {ACTION_LOAD_REMOTE,        on_load_remote, null, "false" },
        {ACTION_NEW_CONVERSATION,   on_new_conversation           },
        {ACTION_OPEN,               on_open                       },
        {ACTION_SAVE,               on_save                       },
        {ACTION_SHOW_CONVERSATIONS, on_show_conversations         },
        {ACTION_STAR,               on_star,                      },
        {ACTION_UNSTAR,             on_unstar,                    },
    };


    public Application.Contact contact { get; private set; }

    public Geary.RFC822.MailboxAddress mailbox { get; private set; }

    private GLib.Cancellable load_cancellable = new GLib.Cancellable();

    private Application.Configuration config;

    [GtkChild] private unowned Gtk.Grid contact_pane;

    [GtkChild] private unowned Hdy.Avatar avatar;

    [GtkChild] private unowned Gtk.Label contact_name;

    [GtkChild] private unowned Gtk.Label contact_address;

    [GtkChild] private unowned Gtk.Button starred_button;

    [GtkChild] private unowned Gtk.Button unstarred_button;

    [GtkChild] private unowned Gtk.ModelButton open_button;

    [GtkChild] private unowned Gtk.ModelButton save_button;

    [GtkChild] private unowned Gtk.ModelButton load_remote_button;

    [GtkChild] private unowned Gtk.Grid deceptive_pane;

    [GtkChild] private unowned Gtk.Label forged_email_label;

    [GtkChild] private unowned Gtk.Label actual_email_label;

    private GLib.SimpleActionGroup actions = new GLib.SimpleActionGroup();


    /** Fired when the remote resources load pref changes */
    public signal void load_remote_resources_changed(bool enabled);


    public ContactPopover(Gtk.Widget relative_to,
                          Application.Contact contact,
                          Geary.RFC822.MailboxAddress mailbox,
                          Application.Configuration config) {

        this.relative_to = relative_to;
        this.contact = contact;
        this.mailbox = mailbox;
        this.config = config;

        this.load_remote_button.role = CHECK;

        this.contact.bind_property("display-name",
                                   this.avatar,
                                   "text",
                                   BindingFlags.SYNC_CREATE);

        this.contact.bind_property("avatar",
                                   this.avatar,
                                   "loadable-icon",
                                   BindingFlags.SYNC_CREATE);

        this.actions.add_action_entries(ACTION_ENTRIES, this);
        insert_action_group(ACTION_GROUP, this.actions);

        contact.changed.connect(this.on_contact_changed);
        update();
    }

    /**
     * Starts loading the avatar for the message's sender.
     */
    public override void destroy() {
        this.contact.changed.disconnect(this.on_contact_changed);
        this.load_cancellable.cancel();
        base.destroy();
    }

    private void update() {
        if (!this.mailbox.is_spoofed()) {
            this.contact_pane.show();
            this.deceptive_pane.hide();

            string display_name = this.contact.display_name;
            this.contact_name.set_text(display_name);

            if (!this.contact.display_name_is_email) {
                this.contact_address.set_text(this.mailbox.address);
            } else {
                this.contact_name.vexpand = true;
                this.contact_name.valign = FILL;
                this.contact_address.hide();
            }

            bool is_desktop = this.contact.is_desktop_contact;

            bool starred = false;
            bool unstarred = false;
            if (is_desktop) {
                starred = this.contact.is_favourite;
                unstarred = !this.contact.is_favourite;
            }
            this.starred_button.set_visible(starred);
            this.unstarred_button.set_visible(unstarred);

            this.open_button.set_visible(is_desktop);
            this.save_button.set_visible(!is_desktop);
            this.load_remote_button.set_visible(!is_desktop);

            GLib.SimpleAction load_remote = (GLib.SimpleAction)
                actions.lookup_action(ACTION_LOAD_REMOTE);
            load_remote.set_state(
                new GLib.Variant.boolean(
                    is_desktop ||
                    Util.Contact.should_load_images(
                        this.contact,
                        this.config)
                )
            );
        } else {
            this.deceptive_pane.show();
            this.contact_pane.hide();

            this.forged_email_label.label = Geary.String.reduce_whitespace(
                this.mailbox.name
            );
            this.actual_email_label.label = this.mailbox.address;
        }
    }

    private async void open() {
        try {
            yield this.contact.open_on_desktop(null);
        } catch (GLib.Error err) {
            debug("Failed to open desktop app for showing contact %s:, %s",
                  this.contact.to_string(), err.message);
        }
    }

    private async void save() {
        try {
            yield this.contact.save_to_desktop(null);
        } catch (GLib.Error err) {
            debug("Failed to open desktop app for saving contact %s:, %s",
                  this.contact.to_string(), err.message);
        }
    }

    private async void set_load_remote_resources(bool enabled) {
        try {
            // Remove all contact email domains from trusted list
            // Otherwise, user may not understand why images are always shown
            if (!enabled) {
                var email_addresses = this.contact.email_addresses;
                foreach (Geary.RFC822.MailboxAddress email in email_addresses) {
                    this.config.remove_images_trusted_domain(email.domain);
                }
            }
            yield this.contact.set_remote_resource_loading(enabled, null);
            load_remote_resources_changed(enabled);
        } catch (GLib.Error err) {
            debug("Failed to set load remote resources for contact %s:, %s",
                  this.contact.to_string(), err.message);
        }
    }

    private async void set_favourite(bool enabled) {
        try {
            yield this.contact.set_favourite(enabled, null);
        } catch (GLib.Error err) {
            debug("Failed to set enabled state for contact %s:, %s",
                  this.contact.to_string(), err.message);
        }
    }

    private void on_contact_changed() {
        update();
    }

    private void on_copy_email() {
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(this.mailbox.to_full_display(), -1);
        clipboard.store();
    }

    private void on_load_remote(GLib.SimpleAction action) {
        bool state = !action.get_state().get_boolean();
        this.set_load_remote_resources.begin(state);
    }

    private void on_new_conversation() {
        var main = this.get_toplevel() as Application.MainWindow;
        if (main != null) {
            main.application.new_composer.begin(this.mailbox);
        }
    }

    private void on_open() {
        this.open.begin();
    }

    private void on_save() {
        this.save.begin();
    }

    private void on_show_conversations() {
        var main = this.get_toplevel() as Application.MainWindow;
        if (main != null) {
            main.show_search_bar("from:%s".printf(this.mailbox.address));
        }
    }

    private void on_star() {
        this.set_favourite.begin(true);
    }

    private void on_unstar() {
        this.set_favourite.begin(false);
    }

    [GtkCallback]
    private void after_closed() {
        GLib.Idle.add(() => {
                this.destroy();
                return GLib.Source.REMOVE;
            } );
    }

}
