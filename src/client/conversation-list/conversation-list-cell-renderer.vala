/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationListCellRenderer : Gtk.CellRenderer {
    private static FormattedConversationData? example_data = null;
    private static bool hover_selected = false;
    
    // Mail message data.
    public FormattedConversationData data { get; set; }
    
    public ConversationListCellRenderer() {
    }
    
    public override void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, 
        out int y_offset, out int width, out int height) {
        if (example_data == null)
            style_changed(widget);
        
        example_data.get_size(widget, cell_area, out x_offset, out y_offset, out width, out height);
    }
    
    public override void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area, 
        Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
        if (data != null)
            data.render(ctx, widget, background_area, cell_area, flags, hover_selected);
    }
    
    // Recalculates size when the style changed.
    // Note: this must be called by the parent TreeView.
    public static void style_changed(Gtk.Widget widget) {
        if (example_data == null) {
            example_data = new FormattedConversationData.create_example();
        }
        
        example_data.calculate_sizes(widget);
    }
    
    // Shows hover effect on all selected cells.
    public static void set_hover_selected(bool hover) {
        hover_selected = hover;
    }
}

