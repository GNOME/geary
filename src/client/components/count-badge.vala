/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Draws the count badge and calculates its dimensions.
 */
public class CountBadge : Geary.BaseObject {
    public const string UNREAD_BG_COLOR = "#888888";
	public const int SPACING = 6;

    private const int FONT_SIZE_MESSAGE_COUNT = 8;

    public int count { get; set; default = 0; }

    private int min = 0;

    /**
     * Creates a count badge.
     * @param min Minimum count to draw.
     */
    public CountBadge(int min) {
        this.min = min;
    }

    public int get_width(Gtk.Widget widget) {
        int width = 0;
        render_internal(widget, null, 0, 0, false, out width, null);

        return width;
    }

    public int get_height(Gtk.Widget widget) {
        int height = 0;
        render_internal(widget, null, 0, 0, false, null, out height);

        return height;
    }

    public void render(Gtk.Widget widget, Cairo.Context? ctx, int x, int y, bool selected) {
        render_internal(widget, ctx, x, y, selected, null, null);
    }

    private void render_internal(Gtk.Widget widget, Cairo.Context? ctx, int x, int y, bool selected,
        out int? width, out int? height) {
        if (count < min) {
            width = 0;
            height = 0;

            return;
        }

        string mails =
            "<span foreground='white' font='%d' weight='bold'> %d </span>"
            .printf(FONT_SIZE_MESSAGE_COUNT, count);

        Pango.Layout layout_num = widget.create_pango_layout(null);
        layout_num.set_markup(mails, -1);
        layout_num.set_alignment(Pango.Alignment.RIGHT);

        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        layout_num.get_pixel_extents(out ink_rect, out logical_rect);
        if (ctx != null) {
            double bg_width = logical_rect.width + SPACING;
            double bg_height = logical_rect.height;
            double radius = bg_height / 2.0;
            double degrees = Math.PI / 180.0;

            // Create rounded rect.
            ctx.new_sub_path();
            ctx.arc(x + bg_width - radius,  y + radius, radius, -90 * degrees, 0 * degrees);
            ctx.arc(x + bg_width - radius,  y + bg_height - radius, radius, 0 * degrees, 90 * degrees);
            ctx.arc(x + radius, y + bg_height - radius, radius, 90 * degrees, 180 * degrees);
            ctx.arc(x + radius, y + radius, radius, 180 * degrees, 270 * degrees);
            ctx.close_path();

            // Colorize our shape.
            Util.Gtk.set_source_color_from_string(ctx, UNREAD_BG_COLOR);
            ctx.fill_preserve();
            ctx.set_line_width(2.0);
            ctx.stroke();

            // Center the text.
            ctx.move_to(x + (bg_width / 2) - logical_rect.width / 2, y);
            Pango.cairo_show_layout(ctx, layout_num);
        }

        width = logical_rect.width + SPACING;
        height = logical_rect.height;
    }
}
