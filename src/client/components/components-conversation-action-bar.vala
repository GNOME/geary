/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Purism SPC
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Draws the conversation action bar.
[GtkTemplate (ui = "/org/gnome/Geary/components-conversation-action-bar.ui")]
public class Components.ConversationActionBar : Gtk.Revealer {
    private ulong owner_notify;

    [GtkChild]
    private Gtk.Box action_box;

    public ConversationActionBar() {
    }

    /**
     * This takes ownership of the ConversationActions and places some of
     * the buttons into the ActionBar.
     */
    public void add_conversation_actions(Components.ConversationActions actions) {
        if (actions.owner == this)
          return;

        actions.take_ownership(this);
        action_box.pack_start(actions.mark_copy_move_buttons, false, false);
        action_box.pack_end(actions.archive_trash_delete_buttons, false, false);
        reveal_child = true;
        this.owner_notify = actions.notify["owner"].connect(() => {
           if (actions.owner != this) {
             reveal_child = false;
             actions.disconnect (this.owner_notify);
           }
        });
    }
}
