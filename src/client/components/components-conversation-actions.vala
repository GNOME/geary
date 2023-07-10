/*
 * Copyright © 2017 Software Freedom Conservancy Inc.
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A container of conversation-related actions.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-conversation-actions.ui")]
public class Components.ConversationActions : Gtk.Box {

    public bool show_conversation_actions { get; construct; }

    public bool show_response_actions { get; construct; }

    public bool pack_justified { get; construct; }

    public FolderPopover copy_move_popover {
        get {
            unowned var popover = this.copy_message_button.popover as FolderPopover;
            return popover;
        }
    }

    public int selected_conversations { get; set; }

    private Geary.Account _account;
    public Geary.Account account {
        get {
            return this._account;
        }
        set {
            this._account = value;
            this.update_conversation_buttons();
        }
    }

    [GtkChild] private unowned Gtk.Box response_buttons { get; }

    [GtkChild] private unowned Gtk.MenuButton mark_message_button { get; }
    [GtkChild] private unowned Gtk.MenuButton copy_message_button { get;  }

    [GtkChild] private unowned Gtk.Box action_buttons { get; }
    [GtkChild] private unowned Gtk.Button archive_button;
    [GtkChild] private unowned Gtk.Button trash_delete_button;

    private bool show_trash_button = true;

    // Load these at construction time
    private Gtk.Image trash_image = new Gtk.Image.from_icon_name("user-trash-symbolic", Gtk.IconSize.MENU);
    private Gtk.Image delete_image = new Gtk.Image.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);

    static construct {
        set_css_name("components-conversation-actions");
    }

    // GObject style constuction to support loading via GTK Builder files
    construct {
        // Assemble the mark menus
        Gtk.Builder menu_builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/components-menu-conversation.ui"
        );
        GLib.MenuModel mark_menu = (MenuModel) menu_builder.get_object(
            "mark_message_menu"
        );

        this.notify["selected-conversations"].connect(() => update_conversation_buttons());
        this.notify["service-provider"].connect(() => update_conversation_buttons());
        this.mark_message_button.popover = new Gtk.Popover.from_model(null, mark_menu);

        this.mark_message_button.toggled.connect((button) => {
            if (button.active)
                mark_message_button_toggled();
        });

        this.response_buttons.set_visible(this.show_response_actions);
        this.action_buttons.set_visible(this.show_conversation_actions);

        if (this.pack_justified) {
            this.action_buttons.hexpand = true;
            this.action_buttons.halign = END;
        }
    }

    public void init(Application.Configuration config) {
        this.copy_message_button.popover = new FolderPopover(config);
        this.bind_property(
            "account", this.copy_message_button.popover,
            "account", BindingFlags.DEFAULT
        );
    }

    public void set_copy_sensitive(bool is_sensitive) {
        this.copy_message_button.sensitive = is_sensitive;
    }

    public void set_mark_sensitive(bool is_sensitive) {
        this.mark_message_button.sensitive = is_sensitive;
    }

    public void show_copy_menu() {
        this.copy_message_button.clicked();
    }

    public void set_mark_inverted() {
        var image = new Gtk.Image.from_icon_name(
            "pan-up-symbolic", Gtk.IconSize.BUTTON
        );
        this.mark_message_button.set_image(image);
    }

    public void update_trash_button(bool show_trash) {
        this.show_trash_button = show_trash;
        update_conversation_buttons();
    }

    /** Fired when the user toggles the mark message button. */
    public signal void mark_message_button_toggled();

    /** Updates tooltip text depending on number of conversations selected. */
    private void update_conversation_buttons() {
        this.mark_message_button.tooltip_text = ngettext(
            "Mark conversation",
            "Mark conversations",
            this.selected_conversations
            );

        this.archive_button.tooltip_text = ngettext(
            "Archive conversation",
            "Archive conversations",
            this.selected_conversations
            );

        if (this.account != null) {
            switch (this.account.information.service_provider) {
            case Geary.ServiceProvider.GMAIL:
                this.copy_message_button.tooltip_text = ngettext(
                    "Add label to conversation",
                    "Add label to conversations",
                    this.selected_conversations
                    );
                this.copy_message_button.set_image(
                    new Gtk.Image.from_icon_name(
                        "tag-symbolic", Gtk.IconSize.BUTTON)
                );
                break;
            default:
                this.copy_message_button.tooltip_text = ngettext(
                    "Copy conversation",
                    "Copy conversations",
                    this.selected_conversations
                    );
                this.copy_message_button.set_image(
                    new Gtk.Image.from_icon_name(
                        "folder-symbolic", Gtk.IconSize.BUTTON)
                );
                break;
            }
        }

        if (this.show_trash_button) {
            this.trash_delete_button.action_name = Action.Window.prefix(
                Application.MainWindow.ACTION_TRASH_CONVERSATION
                );
            this.trash_delete_button.image = trash_image;
            this.trash_delete_button.tooltip_text = ngettext(
                "Move conversation to Trash",
                "Move conversations to Trash",
                this.selected_conversations
                );
        } else {
            this.trash_delete_button.action_name = Action.Window.prefix(
                Application.MainWindow.ACTION_DELETE_CONVERSATION
                );
            this.trash_delete_button.image = delete_image;
            this.trash_delete_button.tooltip_text = ngettext(
                "Delete conversation",
                "Delete conversations",
                this.selected_conversations
                );
        }
    }
}
