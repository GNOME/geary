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

    public override void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area,
        Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
        unread_count.count = counter;

        // Compute x and y locations to right-align and vertically center the count.
        int x = cell_area.x + (cell_area.width - unread_count.get_width(widget)) - HORIZONTAL_MARGIN;
        int y = cell_area.y + ((cell_area.height - unread_count.get_height(widget)) / 2);
        unread_count.render(widget, ctx, x, y, false);
    }

    // This is implemented because it's required; ignore it and look at get_preferred_width() instead.
    public override void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset,
        out int y_offset, out int width, out int height) {
        // Set values to avoid compiler warning.
        x_offset = 0;
        y_offset = 0;
        width = 0;
        height = 0;
    }
}

