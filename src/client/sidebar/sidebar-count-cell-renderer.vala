/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Cell renderer for counter in sidebar.
 */
public class SidebarCountCellRenderer : Gtk.CellRenderer {
    private const int HORIZONTAL_MARGIN = 4;

    public int counter { get; set; }

    private CountBadge unread_count = new CountBadge(1);

    public SidebarCountCellRenderer() {
    }

    public override Gtk.SizeRequestMode get_request_mode() {
        return Gtk.SizeRequestMode.WIDTH_FOR_HEIGHT;
    }

    public override void get_preferred_width(Gtk.Widget widget, out int minimum_size, out int natural_size) {
        unread_count.count = counter;
        minimum_size = unread_count.get_width(widget) + CountBadge.SPACING;
        natural_size = minimum_size;
    }

    public override void snapshot(Gtk.Snapshot snapshot,
                                  Gtk.Widget widget,
                                  Gdk.Rectangle background_area,
                                  Gdk.Rectangle cell_area,
                                  Gtk.CellRendererState flags) {
        this.unread_count.count = this.counter;

        Graphene.Rect cell_rect = { { cell_area.x, cell_area.y } , { cell_area.width, cell_area.height } };
        Cairo.Context ctx = snapshot.append_cairo(cell_rect);
        // Compute x and y locations to right-align and vertically center the count.
        int x = cell_area.x + (cell_area.width - unread_count.get_width(widget)) - HORIZONTAL_MARGIN;
        int y = cell_area.y + ((cell_area.height - unread_count.get_height(widget)) / 2);
        unread_count.render(widget, ctx, x, y, false);
    }
}

