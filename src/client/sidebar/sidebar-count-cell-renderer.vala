/* Copyright 2013 Yorba Foundation
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
    
    public SidebarCountCellRenderer() {
    }
    
    public override Gtk.SizeRequestMode get_request_mode() {
        return Gtk.SizeRequestMode.WIDTH_FOR_HEIGHT;
    }
    
    public override void get_preferred_width(Gtk.Widget widget, out int minimum_size, out int natural_size) {
        minimum_size = render_counter(widget, null, null, false); // Calculate width.
        natural_size = minimum_size;
    }
    
    public override void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area, 
        Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
        render_counter(widget, cell_area, ctx, false);
    }
    
    // Renders the counter.  Returns its own width.
    private int render_counter(Gtk.Widget widget, Gdk.Rectangle? cell_area, Cairo.Context? ctx,
        bool selected) {
        if (counter < 1)
            return 0;
        
        string unread_string = 
            "<span background='#888888' foreground='white' font='%d' weight='bold'> %d </span>"
            .printf(8, counter);
        
        Pango.Layout layout_num = widget.create_pango_layout(null);
        layout_num.set_markup(unread_string, -1);

        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        layout_num.get_pixel_extents(out ink_rect, out logical_rect);
        if (ctx != null && cell_area != null) {
            // Compute x and y locations to right-align and vertically center the count.
            int x = cell_area.x + (cell_area.width - logical_rect.width) - HORIZONTAL_MARGIN;
            int y = cell_area.y + ((cell_area.height - logical_rect.height) / 2);
            ctx.move_to(x, y);
            Pango.cairo_show_layout(ctx, layout_num);
        }
        
        return ink_rect.width + (HORIZONTAL_MARGIN * 2);
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

