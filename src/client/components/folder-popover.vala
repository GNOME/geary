/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/folder-popover.ui")]
public class FolderPopover : Gtk.Popover {

    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.ListBox list_box;

    private int filtered_folder_count = 0;

    public signal void folder_selected(Geary.Folder folder);

    public FolderPopover() {
        list_box.set_filter_func(row_filter);
        list_box.set_sort_func(row_sort);
        this.show.connect(() => search_entry.grab_focus());
        this.hide.connect(() => {
            search_entry.set_text("");
            invalidate_filter();
        });
    }

    public bool has_folder(Geary.Folder folder) {
        return get_row_with_folder(folder) != null;
    }

    public void add_folder(Geary.Folder folder) {
        // Only include remote-backed folders that can be opened
        if (!has_folder(folder)) {
            var remote = folder as Geary.RemoteFolder;
            if (remote != null &&
                !remote.remote_properties.is_openable.is_impossible()) {
                list_box.add(build_row(folder));
                list_box.invalidate_sort();
            }
        }
    }

    public void enable_disable_folder(Geary.Folder folder, bool sensitive) {
        Gtk.ListBoxRow row = get_row_with_folder(folder);
        if (row != null)
            row.sensitive = sensitive;
    }

    public void remove_folder(Geary.Folder folder) {
        Gtk.ListBoxRow row = get_row_with_folder(folder);
        if (row != null)
            list_box.remove(row);
    }

    public Gtk.ListBoxRow? get_row_with_folder(Geary.Folder folder) {
        Gtk.ListBoxRow result = null;
        list_box.foreach((row) => {
            if (row.get_data<Geary.Folder>("folder") == folder)
                result = row as Gtk.ListBoxRow;
        });
        return result;
    }

    public void clear() {
        list_box.foreach((row) => list_box.remove(row));
    }

    private Gtk.ListBoxRow build_row(Geary.Folder folder) {
        Gtk.ListBoxRow row = new Gtk.ListBoxRow();
        row.get_style_context().add_class("geary-folder-popover-list-row");
        row.set_data("folder", folder);

        Gtk.Label label = new Gtk.Label(folder.path.to_string());
        label.set_halign(Gtk.Align.START);
        row.add(label);

        row.show_all();

        return row;
    }

    [GtkCallback]
    private void on_row_activated(Gtk.ListBoxRow? row) {
        if (row != null) {
            Geary.Folder folder = row.get_data<Geary.Folder>("folder");
            folder_selected(folder);
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
        Gtk.Label label = row.get_child() as Gtk.Label;
        if (label.label.down().contains(search_entry.text.down())) {
            filtered_folder_count++;
            return true;
        }
        return false;
    }

    private int row_sort(Gtk.ListBoxRow row1, Gtk.ListBoxRow row2) {
        Geary.Folder folder1 = row1.get_data<Geary.Folder>("folder");
        Geary.Folder folder2 = row2.get_data<Geary.Folder>("folder");
        return folder1.path.compare_to(folder2.path);
    }
}
