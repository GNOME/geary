/* Copyright 2016 Software Freedom Conservancy Inc.
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

    public override void get_preferred_height(Gtk.Widget widget,
                                              out int minimum_size,
                                              out int natural_size) {
        if (example_data == null)
            style_changed(widget);

        minimum_size = natural_size = example_data.get_height();
    }

    public override void get_preferred_width(Gtk.Widget widget,
                                              out int minimum_size,
                                              out int natural_size) {
        // Set width to 1 (rather than 0) to work around certain
        // themes that cause the conversation list to be shown as
        // "squished":
        // https://bugzilla.gnome.org/show_bug.cgi?id=713954
        minimum_size = natural_size = 1;
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

    // This is implemented because it's required; ignore it and look at get_preferred_height() instead.
    public override void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, 
        out int y_offset, out int width, out int height) {
        // Set values to avoid compiler warning.
        x_offset = 0;
        y_offset = 0;
        width = 0;
        height = 0;
    }
}
