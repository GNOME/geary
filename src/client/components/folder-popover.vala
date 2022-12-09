/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/folder-popover.ui")]
public class FolderPopover : Gtk.Popover {

    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.ListBox list_box;
    [GtkChild] private unowned Gtk.Switch move_switch;

    public Geary.Account account {get; set;}

    private int filtered_folder_count = 0;

    public signal void copy_conversation(Geary.Folder folder);
    public signal void move_conversation(Geary.Folder folder);

    public FolderPopover(Application.Configuration config) {
        list_box.set_filter_func(row_filter);
        list_box.set_sort_func(row_sort);
        this.show.connect(() => search_entry.grab_focus());
        this.hide.connect(() => {
            search_entry.set_text("");
            invalidate_filter();
        });
        config.bind("move-messages-on-tag", this.move_switch, "active");
    }

    private void add_folder(Application.FolderContext context, Gee.HashMap<string,string> map) {
        Geary.Folder folder = context.folder;
        // don't allow multiples and don't allow folders that can't be opened (that means they
        // support almost no operations and have no content)
        if (folder.properties.is_openable.is_impossible())
            return;

        // also don't allow local-only or virtual folders, which also have a limited set of
        // operations
        if (folder.properties.is_local_only || folder.properties.is_virtual)
            return;

        // Moving mails to Drafts folder not supported
        switch (folder.account.information.service_provider) {
        case Geary.ServiceProvider.GMAIL:
            if (folder.used_as == Geary.Folder.SpecialUse.DRAFTS)
                return;
            break;
        default:
            break;
        }

        // Ignore special directories already having a dedicated button
        switch (folder.used_as) {
        case Geary.Folder.SpecialUse.ARCHIVE:
        case Geary.Folder.SpecialUse.TRASH:
        case Geary.Folder.SpecialUse.JUNK:
            return;
        default:
            break;
        }

        var row = new FolderPopoverRow(context, map);
        row.show();
        list_box.add(row);
        list_box.invalidate_sort();
    }

    [GtkCallback]
    private void on_map(Gtk.Widget widget) {
        var folders = this.account.list_folders();
        // Build map between path and display name for
        // special directories
        var map = new Gee.HashMap<string,string>();
        foreach (var folder in folders) {
            var context = new Application.FolderContext(folder);
            if (folder.used_as == Geary.Folder.SpecialUse.NONE)
                continue;
            map.set(
                folder.path.to_string().substring(1),
                context.display_name
            );
        }
        foreach (var folder in folders) {
            var context = new Application.FolderContext(folder);
            this.add_folder(context, map);
        }
    }

    [GtkCallback]
    private void on_unmap(Gtk.Widget widget) {
        list_box.foreach((row) => list_box.remove(row));
    }

    [GtkCallback]
    private void on_row_activated(Gtk.ListBoxRow? row) {
        if (row != null) {
            Geary.Folder folder = row.get_data<Geary.Folder>("folder");
            if (this.move_switch.active) {
                move_conversation(folder);
            } else {
                copy_conversation(folder);
            }
        }

        this.hide();
    }

    [GtkCallback]
    private void on_search_entry_activate() {
        if (filtered_folder_count == 1) {
            // Don't use get_row_at_index(0), or you will get the first row of the unfiltered list.
            Gtk.ListBoxRow? row = list_box.get_row_at_y(0);
            if (row != null)
                on_row_activated(row);
        } else if (filtered_folder_count > 0) {
            list_box.get_row_at_y(0).grab_focus();
        }
    }

    [GtkCallback]
    private void on_search_entry_search_changed() {
        invalidate_filter();
        if (this.search_entry.get_text() != "") {
            this.list_box.unselect_all();
        }
    }

    private void invalidate_filter() {
        filtered_folder_count = 0;
        list_box.invalidate_filter();
    }

    private bool row_filter(Gtk.ListBoxRow row) {
        Geary.Folder folder = row.get_data<Geary.Folder>("folder");
        if (folder.path.to_string().down().contains(search_entry.text.down())) {
            filtered_folder_count++;
            return true;
        }
        return false;
    }

    private int row_sort(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        Geary.Folder folder1 = row1.get_data<Geary.Folder>("folder");
        Geary.Folder folder2 = row2.get_data<Geary.Folder>("folder");
        if (folder1.used_as != Geary.Folder.SpecialUse.NONE &&
                folder2.used_as == Geary.Folder.SpecialUse.NONE)
            return -1;
        else if (folder1.used_as == Geary.Folder.SpecialUse.NONE &&
                folder2.used_as != Geary.Folder.SpecialUse.NONE)
            return 1;
        else
            return folder1.path.compare_to(folder2.path);
    }
}
