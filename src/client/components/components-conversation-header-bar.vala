/*
 * Copyright © 2020 Purism SPC
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/components-conversation-header-bar.ui")]
public class Components.ConversationHeaderBar : Gtk.HeaderBar {
    public Components.ConversationActionBar action_bar { get; set; }
    public bool folded { get; set; }

    private ulong owner_notify;
    private Gtk.Widget? reply_forward_buttons;
    private Gtk.Widget? archive_trash_delete_buttons;

    public ConversationHeaderBar() {
    }

    public override void size_allocate(Gtk.Allocation allocation) {
        update_action_bar();
        base.size_allocate(allocation);
    }

    [GtkCallback]
    private void update_action_bar () {
        /* Only show the action_bar when the conversation_header is shown */
        if (parent == null)
            action_bar.reveal_child = false;
        else if (reply_forward_buttons != null && archive_trash_delete_buttons != null)
            if (action_bar.reveal_child && get_allocated_width() > 600) {
                action_bar.reveal_child = false;
                remove_action_parent();
                pack_start(reply_forward_buttons);
                pack_end(archive_trash_delete_buttons);
            } else if (!action_bar.reveal_child && get_allocated_width() < 600) {
                remove_action_parent();
                action_bar.action_box.pack_start(reply_forward_buttons, false, false);
                action_bar.action_box.pack_end(archive_trash_delete_buttons, false, false);
                action_bar.reveal_child = true;
            }
    }

    private void remove_action_parent() {
        if (reply_forward_buttons != null && reply_forward_buttons.parent != null)
            reply_forward_buttons.parent.remove(reply_forward_buttons);
        if (archive_trash_delete_buttons != null && archive_trash_delete_buttons.parent != null)
            archive_trash_delete_buttons.parent.remove(archive_trash_delete_buttons);
    }

    public void add_conversation_actions(Components.ConversationActions actions) {
        if (actions.owner != this) {
            actions.take_ownership(this);
            pack_start(actions.mark_copy_move_buttons);
            pack_end(actions.find_button);   

            reply_forward_buttons = actions.reply_forward_buttons;
            archive_trash_delete_buttons = actions.archive_trash_delete_buttons;
            update_action_bar();
            this.owner_notify = actions.notify["owner"].connect(() => {
                if (actions.owner != this) {
                    action_bar.reveal_child = false;
                    reply_forward_buttons = null;
                    archive_trash_delete_buttons = null;
                    actions.disconnect (this.owner_notify);
                }
            });
        }
    }
}
