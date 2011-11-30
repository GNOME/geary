/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Stores formatted data for a message.
public class FormattedMessageData : Object {
    private const string STYLE_EXAMPLE = "Gg"; // Use both upper and lower case to get max height.
    private const int LINE_SPACING = 4;
    private const int TEXT_LEFT = LINE_SPACING * 2 + IconFactory.instance.UNREAD_ICON_SIZE;
    
    private const int FONT_SIZE_DATE = 11;
    private const int FONT_SIZE_SUBJECT = 9;
    private const int FONT_SIZE_FROM = 11;
    private const int FONT_SIZE_PREVIEW = 8;
    
    private static int cell_height = -1;
    private static int preview_height = -1;
    
    public Geary.Email email { get; private set; default = null; }
    public bool is_unread { get; private set; default = false; }
    public string date { get; private set; default = ""; } 
    public string from { get; private set; default = ""; }
    public string subject { get; private set; default = ""; }
    public string? body { get; private set; default = null; } // optional
    public int num_emails { get; private set; default = 1; }
    
    private FormattedMessageData(bool is_unread, string date, string from, string subject, 
        string preview, int num_emails) {
        this.is_unread = is_unread;
        this.date = date;
        this.from = from;
        this.subject = subject;
        this.body = preview;
        this.num_emails = num_emails;
    }
    
    // Creates a formatted message data from an e-mail.
    public FormattedMessageData.from_email(Geary.Email email, int num_emails, bool unread) {
        assert(email.fields.fulfills(MessageListStore.REQUIRED_FIELDS));
        
        string preview = "";
        if (email.fields.fulfills(Geary.Email.Field.PREVIEW) && email.preview != null)
            preview = email.preview.buffer.to_utf8();
        
        string from = (email.from != null && email.from.size > 0) ? email.from[0].get_short_address() : "";
        
        this(unread, Date.pretty_print(email.date.value), from, email.subject.value, 
            Geary.String.reduce_whitespace(preview), num_emails);
        
        this.email = email;
    }
    
    // Creates an example message (used interally for styling calculations.)
    public FormattedMessageData.create_example() {
        this(false, STYLE_EXAMPLE, STYLE_EXAMPLE, STYLE_EXAMPLE, STYLE_EXAMPLE + "\n" +
            STYLE_EXAMPLE, 1);
    }
    
    public void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area, 
        Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
        render_internal(widget, cell_area, ctx);
    }
    
    // Call this on style changes.
    public void calculate_sizes(Gtk.Widget widget) {
        render_internal(widget, null, null, true);
    }
    
    // Must call calculate_sizes() first.
    public void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, 
        out int y_offset, out int width, out int height) {
        assert(cell_height != -1); // ensures calculate_sizes() was called.
        
        x_offset = 0;
        y_offset = 0;
        width = 0;
        height = cell_height;
    }
    
    // Can be used for rendering or calculating height.
    private void render_internal(Gtk.Widget widget, Gdk.Rectangle? cell_area = null, 
        Cairo.Context? ctx = null, bool recalc_dims = false) {
        
        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        
        int y = LINE_SPACING + (cell_area != null ? cell_area.y : 0);
        
        // Date field.
        Pango.FontDescription font_date = new Pango.FontDescription();
        font_date.set_size(FONT_SIZE_DATE * Pango.SCALE);
        Pango.AttrList list_date = new Pango.AttrList();
        list_date.insert(Pango.attr_foreground_new(10000, 10000, 55000)); // muted blue
        Pango.Layout layout_date = widget.create_pango_layout(null);
        layout_date.set_font_description(font_date);
        layout_date.set_attributes(list_date);
        layout_date.set_text(date, -1);
        layout_date.set_alignment(Pango.Alignment.RIGHT);
        layout_date.get_pixel_extents(out ink_rect, out logical_rect);
        if (ctx != null && cell_area != null) {
            ctx.move_to(cell_area.width - cell_area.x - ink_rect.width - ink_rect.x - LINE_SPACING, y);
            Pango.cairo_show_layout(ctx, layout_date);
        }
        
        // From field.
        Pango.FontDescription font_from = new Pango.FontDescription();
        font_from.set_size(FONT_SIZE_FROM * Pango.SCALE);
        font_from.set_weight(Pango.Weight.BOLD);
        Pango.Layout layout_from = widget.create_pango_layout(null);
        layout_from.set_font_description(font_from);
        layout_from.set_text(from, -1);
        layout_from.set_ellipsize(Pango.EllipsizeMode.END);
        if (ctx != null && cell_area != null) {
            layout_from.set_width((cell_area.width - ink_rect.width - ink_rect.x - LINE_SPACING -
                TEXT_LEFT)
            * Pango.SCALE);
            ctx.move_to(cell_area.x + TEXT_LEFT, y);
            Pango.cairo_show_layout(ctx, layout_from);
        }
        
        y += ink_rect.height + ink_rect.y + LINE_SPACING;
        
        // Subject field.
        Pango.FontDescription font_subject = new Pango.FontDescription();
        font_subject.set_size(FONT_SIZE_SUBJECT * Pango.SCALE);
        Pango.Layout layout_subject = widget.create_pango_layout(null);
        layout_subject.set_font_description(font_subject);
        layout_subject.set_text(subject, -1);
        if (cell_area != null)
            layout_subject.set_width((cell_area.width - TEXT_LEFT) * Pango.SCALE);
        layout_subject.set_ellipsize(Pango.EllipsizeMode.END);
        layout_date.get_pixel_extents(out ink_rect, out logical_rect);
        if (ctx != null && cell_area != null) {
            ctx.move_to(cell_area.x + TEXT_LEFT, y);
            Pango.cairo_show_layout(ctx, layout_subject);
        }
        
        y += ink_rect.height + ink_rect.y + LINE_SPACING;
        
        // Number of e-mails field.
        int num_email_width = 0;
        if (num_emails > 1) {
            Pango.Rectangle? num_ink_rect;
            Pango.Rectangle? num_logical_rect;
            string mails = 
                "<span background='#999999' foreground='white' size='x-small' weight='bold'> %d </span>"
                .printf(num_emails);
                
            Pango.Layout layout_num = widget.create_pango_layout(null);
            layout_num.set_markup(mails, -1);
            layout_num.set_alignment(Pango.Alignment.RIGHT);
            layout_num.get_pixel_extents(out num_ink_rect, out num_logical_rect);
            if (ctx != null && cell_area != null) {
                ctx.move_to(cell_area.width - cell_area.x - num_ink_rect.width - num_ink_rect.x - 
                    LINE_SPACING, y);
                Pango.cairo_show_layout(ctx, layout_num);
            }
            
            num_email_width = num_ink_rect.width + (LINE_SPACING * 3);
        }
        
        // Body preview.
        Pango.FontDescription font_preview = new Pango.FontDescription();
        font_preview.set_size(FONT_SIZE_PREVIEW * Pango.SCALE);
        Pango.AttrList list_preview = new Pango.AttrList();
        list_preview.insert(Pango.attr_foreground_new(28671, 28671, 28671)); // #777
        
        Pango.Layout layout_preview = widget.create_pango_layout(null);
        layout_preview.set_font_description(font_preview);
        layout_preview.set_attributes(list_preview);
        
        layout_preview.set_text(body != null ? body : "\n\n", -1);
        layout_preview.set_wrap(Pango.WrapMode.WORD);
        layout_preview.set_ellipsize(Pango.EllipsizeMode.END);
        if (ctx != null && cell_area != null) {
            layout_preview.set_width((cell_area.width - TEXT_LEFT - num_email_width) * Pango.SCALE);
            layout_preview.set_height(preview_height * Pango.SCALE);
            
            ctx.move_to(cell_area.x + TEXT_LEFT, y);
            Pango.cairo_show_layout(ctx, layout_preview);
        } else {
            layout_preview.set_width(int.MAX);
            layout_preview.set_height(int.MAX);
        }
        
        if (recalc_dims) {
            layout_preview.get_pixel_extents(out ink_rect, out logical_rect);
            preview_height = ink_rect.height + ink_rect.y + LINE_SPACING;
            cell_height = y + preview_height;
        }
        
        // Unread indicator.
        if (is_unread) {
            Gdk.cairo_set_source_pixbuf(ctx, IconFactory.instance.unread, cell_area.x + LINE_SPACING,
                cell_area.y + (cell_area.height / 2) - (IconFactory.instance.UNREAD_ICON_SIZE / 2));
            ctx.paint();
        }
    }
}

public class MessageListCellRenderer : Gtk.CellRenderer {
    private static FormattedMessageData? example_data = null;
    
    // Mail message data.
    public FormattedMessageData data { get; set; }
    
    public MessageListCellRenderer() {
    }
    
    public override void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, 
        out int y_offset, out int width, out int height) {
        if (example_data == null)
            style_changed(widget);
        
        example_data.get_size(widget, cell_area, out x_offset, out y_offset, out width, out height);
    }
    
    public override void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area, 
        Gdk.Rectangle cell_area, Gtk.CellRendererState flags) {
        if (data == null)
            return;
        
        data.render(ctx, widget, background_area, cell_area, flags);
    }
    
    // Recalculates size when the style changed.
    // Note: this must be called by the parent TreeView.
    public static void style_changed(Gtk.Widget widget) {
        if (example_data == null) {
            example_data = new FormattedMessageData.create_example();
        }
        
        example_data.calculate_sizes(widget);
    }
}

