/* Copyright © 2020 Purism SPC
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Cell renderer for the expander in the sidebar.
 */
public class SidebarExpanderRenderer : Gtk.CellRendererPixbuf {
    public signal void toggle(Gtk.TreePath path);
    public weak Gtk.Widget widget { get; set; }
    public SidebarExpanderRenderer(Gtk.Widget widget) {
        this.widget = widget;
        xalign = 1;
        mode = Gtk.CellRendererMode.ACTIVATABLE;
        notify["is-expanded"].connect (update_arrow);
        update_arrow();
    }

    private void update_arrow() {
        if (is_expanded)
            this.icon_name = "go-down-symbolic";
        else
            this.icon_name = "go-next-symbolic";
    }

    public override bool activate (Gdk.Event event,
                                   Gtk.Widget widget,
                                   string path,
                                   Gdk.Rectangle background_area,
                                   Gdk.Rectangle cell_area,
                                   Gtk.CellRendererState flags) {
        toggle(new Gtk.TreePath.from_string (path));
        return true;
    }
}

