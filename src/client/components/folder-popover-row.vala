/* Copyright 2022 Cédric Bellegarde <cedric.bellegarde@adishatz.org>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/folder-popover-row.ui")]
public class FolderPopoverRow : Gtk.ListBoxRow {

    [GtkChild] private unowned Gtk.Image image;
    [GtkChild] private unowned Gtk.Label label;

    public FolderPopoverRow(Application.FolderContext context, Gee.HashMap<string,string> map) {
        string[] as_array = context.folder.path.as_array();

        if (map.has_key(as_array[0])) {
            as_array[0] = map[as_array[0]];
        }

        var i = 0;
        foreach (string name in as_array) {
            as_array[i] = GLib.Markup.escape_text(name);
            i += 1;
        }

        this.set_data("folder", context.folder);
        this.image.icon_name = context.icon_name;

        this.label.set_markup(string.joinv("<span alpha='30%'> / </span>", as_array));
        this.label.query_tooltip.connect(Util.Gtk.query_tooltip_label);
    }
}
