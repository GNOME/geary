/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Container for actions for a conversation generally placed into the ActionBar or HeaderBar
 * The user of the actions needs to take ownership before they can place the actions in a container
 */
public class Components.ConversationActions : GLib.Object {
    public Gtk.Widget? owner { get; private set; }
    // Copy and Move popovers
    public FolderPopover copy_folder_menu { get; private set; default = new FolderPopover(); }
    public FolderPopover move_folder_menu { get; private set; default = new FolderPopover(); }
    // How many conversations are selected right now. Should automatically be updated.
    public int selected_conversations { get; set; }
    public bool find_open { get; set; }

    public Gtk.Box mark_copy_move_buttons { get; private set; }
    public Gtk.MenuButton mark_message_button { get; private set; }
    public Gtk.MenuButton copy_message_button { get; private set; }
    public Gtk.MenuButton move_message_button { get; private set; }

    public Gtk.Box reply_forward_buttons { get; private set; }

    public Gtk.Box archive_trash_delete_buttons { get; private set; }
    private Gtk.Button archive_button;
    private Gtk.Button trash_delete_button;

    public Gtk.ToggleButton find_button { get; private set; }

    private bool show_trash_button = true;

    // Load these at construction time
    private Gtk.Image trash_image = new Gtk.Image.from_icon_name("user-trash-symbolic", Gtk.IconSize.MENU);
    private Gtk.Image delete_image = new Gtk.Image.from_icon_name("edit-delete-symbolic", Gtk.IconSize.MENU);

    public ConversationActions() {
        Gtk.Builder builder =
            new Gtk.Builder.from_resource("/org/gnome/Geary/components-conversation-actions.ui");
        // Assemble the mark menus
        Gtk.Builder menu_builder =
            new Gtk.Builder.from_resource("/org/gnome/Geary/components-main-toolbar-menus.ui");
        MenuModel mark_menu = (MenuModel) menu_builder.get_object("mark_message_menu");

        this.mark_copy_move_buttons = (Gtk.Box) builder.get_object("mark_copy_move_buttons");
        this.mark_message_button = (Gtk.MenuButton) builder.get_object("mark_message_button");
        this.copy_message_button = (Gtk.MenuButton) builder.get_object("copy_message_button");
        this.move_message_button = (Gtk.MenuButton) builder.get_object("move_message_button");

        this.reply_forward_buttons = (Gtk.Box) builder.get_object("reply_forward_buttons");

        this.archive_trash_delete_buttons = (Gtk.Box) builder.get_object("archive_trash_delete_buttons");
        this.archive_button = (Gtk.Button) builder.get_object("archive_button");
        this.trash_delete_button = (Gtk.Button) builder.get_object("trash_delete_button");

        this.find_button = (Gtk.ToggleButton) builder.get_object("find_button");

        this.bind_property("find-open", this.find_button, "active",
                           BindingFlags.SYNC_CREATE | BindingFlags.BIDIRECTIONAL);
        this.notify["selected-conversations"].connect(() => update_conversation_buttons());
        this.mark_message_button.popover = new Gtk.Popover.from_model(null, mark_menu);
        this.copy_message_button.popover = copy_folder_menu;
        this.move_message_button.popover = move_folder_menu;
    }

    /** Sets the new owner and removes the previous owner and parents of the single actions */
    public void take_ownership(Gtk.Widget? new_owner) {
        remove_parent(mark_copy_move_buttons);
        remove_parent(reply_forward_buttons);
        remove_parent(archive_trash_delete_buttons);
        remove_parent(find_button);
        owner = new_owner;
    }

    private void remove_parent (Gtk.Widget widget) {
        if (widget.parent != null)
            widget.parent.remove(widget);
    }

    public void update_trash_button(bool show_trash) {
        this.show_trash_button = show_trash;
        update_conversation_buttons();
    }

    /** Updates tooltip text depending on number of conversations selected. */
    private void update_conversation_buttons() {
        this.mark_message_button.tooltip_text = ngettext(
            "Mark conversation",
            "Mark conversations",
            this.selected_conversations
            );
        this.copy_message_button.tooltip_text = ngettext(
            "Add label to conversation",
            "Add label to conversations",
            this.selected_conversations
            );
        this.move_message_button.tooltip_text = ngettext(
            "Move conversation",
            "Move conversations",
            this.selected_conversations
            );
        this.archive_button.tooltip_text = ngettext(
            "Archive conversation",
            "Archive conversations",
            this.selected_conversations
            );

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
