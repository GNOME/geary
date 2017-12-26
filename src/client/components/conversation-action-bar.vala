/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A context-sensitive set of action buttons for a conversation.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-action-bar.ui")]
public class ConversationActionBar : Gtk.ActionBar {

    private Geary.Account? account = null;

    private bool has_archive = false;
    private bool has_trash = false;

    private FolderPopover copy_folder_menu = new FolderPopover();
    private FolderPopover move_folder_menu = new FolderPopover();

    [GtkChild]
    private Gtk.Grid flag_actions;
    [GtkChild]
    private Gtk.Button mark_read_action;
    [GtkChild]
    private Gtk.Button mark_unread_action;
    [GtkChild]
    private Gtk.Button mark_starred_action;
    [GtkChild]
    private Gtk.Button mark_unstarred_action;

    [GtkChild]
    private Gtk.Grid folder_actions;
    [GtkChild]
    private Gtk.Button archive_action;
    [GtkChild]
    private Gtk.Button restore_action;
    [GtkChild]
    private Gtk.MenuButton copy_action;
    [GtkChild]
    private Gtk.MenuButton move_action;

    [GtkChild]
    private Gtk.Grid destructive_actions;
    [GtkChild]
    private Gtk.Button junk_action;
    [GtkChild]
    private Gtk.Button trash_action;
    [GtkChild]
    private Gtk.Button delete_action;


    public ConversationActionBar() {
        this.copy_action.popover = copy_folder_menu;
        this.move_action.popover = move_folder_menu;
    }

    public void set_account(Geary.Account account) {
        if (this.account != null) {
            this.account.folders_special_type.disconnect(on_special_folder_changed);
        }

        this.account = account;
        this.account.folders_special_type.connect(on_special_folder_changed);
        update_account();
    }

    public void update_location(Geary.Folder location) {
        Gtk.Button? primary_action = null;
        bool show_flag_actions = false;
        bool show_folder_actions = false;
        bool show_junk = false;
        bool show_trash = false;
        bool show_delete = false;

        switch (location.special_folder_type) {
        case Geary.SpecialFolderType.INBOX:
            if (this.has_archive) {
                primary_action = archive_action;
            }
            show_flag_actions = true;
            show_folder_actions = true;
            show_junk = true;
            show_trash = true;
            break;

        case Geary.SpecialFolderType.ARCHIVE:
        case Geary.SpecialFolderType.NONE:
            primary_action = restore_action;
            show_flag_actions = true;
            show_folder_actions = true;
            show_junk = true;
            show_trash = true;
            break;

        case Geary.SpecialFolderType.SENT:
            show_flag_actions = true;
            show_trash = true;
            break;

        case Geary.SpecialFolderType.DRAFTS:
            show_trash = true;
            break;

        case Geary.SpecialFolderType.TRASH:
            primary_action = restore_action;
            show_junk = true;
            show_delete = true;
            break;

        case Geary.SpecialFolderType.SPAM:
            primary_action = restore_action;
            show_delete = true;
            break;

        case Geary.SpecialFolderType.OUTBOX:
            show_delete = true;
            break;

        default:
            // XXX remainder (Search, All, Flagged, etc) are all
            // conversation specific, so examine it/them and work out
            // what to do here
            show_flag_actions = true;
            break;
        }

        // XXX just always hide these for now while the UX is sorted out
        //this.flag_actions.set_visible(show_flag_actions);
        this.flag_actions.set_visible(false);
        update_action_pair(this.mark_read_action, this.mark_unread_action);
        update_action_pair(this.mark_starred_action, this.mark_unstarred_action);

        this.folder_actions.set_visible(primary_action != null || show_folder_actions);
        this.archive_action.set_visible(primary_action == this.archive_action);
        this.restore_action.set_visible(primary_action == this.restore_action);
        this.copy_action.set_visible(show_folder_actions);
        this.move_action.set_visible(show_folder_actions);

        if (show_trash && !this.has_trash) {
            show_trash = false;
            show_delete = true;
        }
        this.destructive_actions.set_visible(
            show_junk || show_trash || show_delete
        );
        this.junk_action.set_visible(show_junk);
        this.trash_action.set_visible(show_trash);
        this.delete_action.set_visible(show_delete && !show_trash);
    }

    private void update_account() {
        try {
            this.has_archive = (
                this.account.get_special_folder(Geary.SpecialFolderType.ARCHIVE) != null
            );
        } catch (Error err) {
            debug("Could not get Archive for account: %s", this.account.to_string());
        }
        try {
            this.has_trash = (
                this.account.get_special_folder(Geary.SpecialFolderType.TRASH) != null
            );
        } catch (Error err) {
            debug("Could not get Trash for account: %s", this.account.to_string());
        }
    }

    private inline void update_action_pair(Gtk.Button primary, Gtk.Button secondary) {
        bool show_primary = true;
        string? secondary_action_name = secondary.get_action_name();
        MainWindow? window = get_toplevel() as MainWindow;
        if (window != null && secondary_action_name != null) {
            Action? secondary_action = window.lookup_action(
                secondary_action_name.substring(4) // chop off the "win."
            );
            if (secondary_action != null) {
                show_primary = !secondary_action.get_enabled();
            }
        }

        primary.set_visible(show_primary);
        secondary.set_visible(!show_primary);
    }

    private void on_special_folder_changed() {
        update_account();
    }

}
