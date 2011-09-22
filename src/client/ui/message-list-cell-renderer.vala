/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Stores formatted data for a message.
public class FormattedMessageData : Object {
    public bool is_unread { get; private set; default = false; }
    public string date { get; private set; default = ""; } 
    public string from { get; private set;  default = ""; }
    public string subject { get; private set; default = ""; }
    public string? body { get; private set; default = null; } // optional
    
    public FormattedMessageData(bool is_unread, string date, string from, string subject, 
        string preview) {
        this.is_unread = is_unread;
        this.date = "<span foreground='blue'>%s</span>".printf(Geary.String.escape(date));
        this.from = "<b>%s</b>".printf(Geary.String.escape(from));
        this.subject = "<small>%s</small>".printf(Geary.String.escape(subject));
        this.body = "<span size='x-small' foreground='#777777'>%s</span>".printf(
            Geary.String.escape(preview));
    }
    
    // Creates a formatted message data from an e-mail.
    public FormattedMessageData.from_email(Geary.Email email) {
        assert(email.fields.fulfills(MessageListStore.REQUIRED_FIELDS));
        
        StringBuilder builder = new StringBuilder();
        if (email.fields.fulfills(Geary.Email.Field.BODY)) {
            try {
                Geary.Memory.AbstractBuffer buffer = email.get_message().
                    get_first_mime_part_of_content_type("text/plain");
                builder.append(buffer.to_utf8());
            } catch (Error e) {
                debug("Error displaying message body: %s".printf(e.message));
            }
        }
        
        this(email.properties.is_unread(), Date.pretty_print(email.date.value),
            email.from[0].get_short_address(), email.subject.value, 
            Geary.String.escape(make_preview(builder.str)));
    }
    
    // Distills an e-mail body into a preview by removing extra spaces, html, etc.
    private static string make_preview(string body) {
        // Remove newlines and tabs.
        string preview = body.replace("\n", " ").replace("\r", " ").replace("\t", " ");
        
        // Remove HTML
        // TODO: needs to strip tags, special chars
        
        // Remove extra space and return.
        // TODO: remove redundant spaces within string
        return preview.strip();
    }
}

public class MessageListCellRenderer : Gtk.CellRenderer {
    private const int LINE_SPACING = 4;
    private const int UNREAD_ICON_SIZE = 12;
    private const int TEXT_LEFT = LINE_SPACING * 2 + UNREAD_ICON_SIZE;
    private const string STYLE_EXAMPLE = "Gg"; // Use both upper and lower case to get max height.
    
    private static int cell_height = -1;
    private static int preview_height = -1;
    private static FormattedMessageData? example_data = null;
    private static Gdk.Pixbuf? unread_pixbuf = null;
    
    // Mail message data.
    public FormattedMessageData data {get; set;}
    
    public MessageListCellRenderer() {
    }
    
    public override void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, 
        out int y_offset, out int width, out int height) {
        
        if (cell_height == -1 || preview_height == -1 || example_data == null)
            style_changed(widget);
        
        if (&x_offset != null)
            x_offset = 0;
        if (&y_offset != null)
            y_offset = 0;
        if (&width != null)
            width = 0;
        if (&height != null)
            height = cell_height;
    }
    
    public override void render(Gdk.Window window, Gtk.Widget widget, Gdk.Rectangle background_area, 
        Gdk.Rectangle cell_area, Gdk.Rectangle expose_area, Gtk.CellRendererState flags) {
        
        Cairo.Context ctx = Gdk.cairo_create(window);
        Gdk.cairo_rectangle (ctx, expose_area);
        ctx.clip();
        
        if (data == null)
            return;
        
        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        
        int y = LINE_SPACING + expose_area.y;
        
        // Date field.
        Pango.Layout layout_date = widget.create_pango_layout(null);
        layout_date.set_markup(data.date, -1);
        layout_date.set_alignment(Pango.Alignment.RIGHT);
        layout_date.get_pixel_extents(out ink_rect, out logical_rect);
        ctx.move_to(expose_area.width - expose_area.x - ink_rect.width - ink_rect.x - LINE_SPACING, y);
        Pango.cairo_show_layout(ctx, layout_date);
        
        // From field.
        Pango.Layout layout_from = widget.create_pango_layout(null);
        layout_from.set_markup(data.from, -1);
        layout_from.set_width((expose_area.width - ink_rect.width - ink_rect.x - LINE_SPACING - TEXT_LEFT)
            * Pango.SCALE);
        layout_from.set_ellipsize(Pango.EllipsizeMode.END);
        ctx.move_to(expose_area.x + TEXT_LEFT, y);
        Pango.cairo_show_layout(ctx, layout_from);
        
        y += ink_rect.height + ink_rect.y + LINE_SPACING;
        
        // Subject field.
        Pango.Layout layout_subject = widget.create_pango_layout(null);
        layout_subject.set_markup(data.subject, -1);
        layout_subject.set_width((expose_area.width - TEXT_LEFT) * Pango.SCALE);
        layout_subject.set_ellipsize(Pango.EllipsizeMode.END);
        layout_date.get_pixel_extents(out ink_rect, out logical_rect);
        ctx.move_to(expose_area.x + TEXT_LEFT, y);
        Pango.cairo_show_layout(ctx, layout_subject);
        
        y += ink_rect.height + ink_rect.y + LINE_SPACING;
        
        // Body preview.
        Pango.Layout layout_preview = widget.create_pango_layout(null);
        layout_preview.set_markup(data.body, -1);
        layout_preview.set_width((expose_area.width - TEXT_LEFT) * Pango.SCALE);
        layout_preview.set_height(preview_height * Pango.SCALE);
        layout_preview.set_wrap(Pango.WrapMode.WORD);
        layout_preview.set_ellipsize(Pango.EllipsizeMode.END);
        ctx.move_to(expose_area.x + TEXT_LEFT, y);
        Pango.cairo_show_layout(ctx, layout_preview);
        
        // Unread indicator.
        if (data.is_unread) {
            if (unread_pixbuf == null) {
                try {
                    unread_pixbuf = Gtk.IconTheme.get_default().load_icon(Gtk.Stock.YES, 
                        UNREAD_ICON_SIZE, 0);
                } catch (Error e) {
                    warning("Couldn't load icon. Error: " + e.message);
                }
            }
            
            Gdk.cairo_set_source_pixbuf(ctx, unread_pixbuf, expose_area.x + LINE_SPACING, 
                expose_area.y + (expose_area.height / 2) - (UNREAD_ICON_SIZE / 2));
            ctx.paint();
        }
    }
    
    // Recalculates size when the style changed.
    // Note: this must be called by the parent TreeView.
    public static void style_changed(Gtk.Widget widget) {
        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        Pango.Layout layout;
        if (example_data == null) {
            example_data = new FormattedMessageData(false, STYLE_EXAMPLE, STYLE_EXAMPLE, STYLE_EXAMPLE, 
                STYLE_EXAMPLE + "\n" + STYLE_EXAMPLE);
        }
        
        cell_height = LINE_SPACING;
        
        // Date
        layout = widget.create_pango_layout(null);
        layout.set_markup(example_data.date, -1);
        layout.get_pixel_extents(out ink_rect, out logical_rect);
        cell_height += ink_rect.height + ink_rect.y + LINE_SPACING;
        
        // Subject
        layout = widget.create_pango_layout(null);
        layout.set_markup(example_data.subject, -1);
        layout.get_pixel_extents(out ink_rect, out logical_rect);
        cell_height += ink_rect.height + ink_rect.y + LINE_SPACING;
        
        // Body preview
        layout = widget.create_pango_layout(null);
        layout.set_markup(example_data.body, -1);
        layout.set_width(int.MAX);
        layout.set_height(int.MAX);
        layout.set_wrap(Pango.WrapMode.WORD);
        layout.set_ellipsize(Pango.EllipsizeMode.END);
        layout.get_pixel_extents(out ink_rect, out logical_rect);
        preview_height = ink_rect.height + ink_rect.y + LINE_SPACING;
        
        cell_height += preview_height;
    }
}

