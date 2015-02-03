/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Stores formatted data for a message.
public class FormattedConversationData : Geary.BaseObject {
    public const int LINE_SPACING = 6;
    
    private const string ME = _("Me");
    private const string STYLE_EXAMPLE = "Gg"; // Use both upper and lower case to get max height.
    private const int TEXT_LEFT = LINE_SPACING * 2 + IconFactory.UNREAD_ICON_SIZE;
    private const double DIM_TEXT_AMOUNT = 0.05;
    private const double DIM_PREVIEW_TEXT_AMOUNT = 0.25;
    
    private const int FONT_SIZE_DATE = 10;
    private const int FONT_SIZE_SUBJECT = 9;
    private const int FONT_SIZE_FROM = 11;
    private const int FONT_SIZE_PREVIEW = 8;
    
    private class ParticipantDisplay : Geary.BaseObject, Gee.Hashable<ParticipantDisplay> {
        public string key;
        public Geary.RFC822.MailboxAddress address;
        public bool is_unread;
        
        public ParticipantDisplay(Geary.RFC822.MailboxAddress address, bool is_unread) {
            key = address.as_key();
            this.address = address;
            this.is_unread = is_unread;
        }
        
        public string get_full_markup(string normalized_account_key) {
            return get_as_markup((key == normalized_account_key) ? ME : address.get_short_address());
        }
        
        public string get_short_markup(string normalized_account_key) {
            if (key == normalized_account_key)
                return get_as_markup(ME);
            
            string short_address = address.get_short_address().strip();
            
            if (", " in short_address) {
                // assume address is in Last, First format
                string[] tokens = short_address.split(", ", 2);
                short_address = tokens[1].strip();
                if (Geary.String.is_empty(short_address))
                    return get_full_markup(normalized_account_key);
            }
            
            // use first name as delimited by a space
            string[] tokens = short_address.split(" ", 2);
            if (tokens.length < 1)
                return get_full_markup(normalized_account_key);
            
            string first_name = tokens[0].strip();
            if (Geary.String.is_empty_or_whitespace(first_name))
                return get_full_markup(normalized_account_key);
            
            return get_as_markup(first_name);
        }
        
        private string get_as_markup(string participant) {
            return "%s%s%s".printf(
                is_unread ? "<b>" : "", Geary.HTML.escape_markup(participant), is_unread ? "</b>" : "");
        }
        
        public bool equal_to(ParticipantDisplay other) {
            if (this == other)
                return true;
            
            return key == other.key;
        }
        
        public uint hash() {
            return key.hash();
        }
    }
    
    private static int cell_height = -1;
    private static int preview_height = -1;
    
    public bool is_unread { get; set; }
    public bool is_flagged { get; set; }
    public string date { get; private set; }
    public string subject { get; private set; }
    public string? body { get; private set; default = null; } // optional
    public int num_emails { get; set; }
    public Geary.Email? preview { get; private set; default = null; }
    
    private Geary.App.Conversation? conversation = null;
    private string? account_owner_email = null;
    private bool use_to = true;
    private CountBadge count_badge = new CountBadge(2);
    
    // Creates a formatted message data from an e-mail.
    public FormattedConversationData(Geary.App.Conversation conversation, Geary.Email preview,
        Geary.Folder folder, string account_owner_email) {
        assert(preview.fields.fulfills(ConversationListStore.REQUIRED_FIELDS));
        
        this.conversation = conversation;
        this.account_owner_email = account_owner_email;
        use_to = (folder != null) && folder.special_folder_type.is_outgoing();
        
        // Load preview-related data.
        update_date_string();
        this.subject = EmailUtil.strip_subject_prefixes(preview);
        this.body = Geary.String.reduce_whitespace(preview.get_preview_as_string());
        this.preview = preview;
        
        // Load conversation-related data.
        this.is_unread = conversation.is_unread();
        this.is_flagged = conversation.is_flagged();
        this.num_emails = conversation.get_count();
    }
    
    public bool update_date_string() {
        // get latest email *in folder* for the conversation's date, fall back on out-of-folder
        Geary.Email? latest = conversation.get_latest_recv_email(Geary.App.Conversation.Location.IN_FOLDER_OUT_OF_FOLDER);
        if (latest == null || latest.properties == null)
            return false;
        
        // conversation list store sorts by date-received, so display that instead of sender's
        // Date:
        string new_date = Date.pretty_print(latest.properties.date_received,
            GearyApplication.instance.config.clock_format);
        if (new_date == date)
            return false;
        
        date = new_date;
        
        return true;
    }
    
    // Creates an example message (used interally for styling calculations.)
    public FormattedConversationData.create_example() {
        this.is_unread = false;
        this.is_flagged = false;
        this.date = STYLE_EXAMPLE;
        this.subject = STYLE_EXAMPLE;
        this.body = STYLE_EXAMPLE + "\n" + STYLE_EXAMPLE;
        this.num_emails = 1;
    }
    
    private uint8 gdk_to_rgb(double gdk) {
        return (uint8) (gdk.clamp(0.0, 1.0) * 255.0);
    }
    
    private Gdk.RGBA dim_rgba(Gdk.RGBA rgba, double amount) {
        amount = amount.clamp(0.0, 1.0);
        
        // can't use ternary in struct initializer due to this bug:
        // https://bugzilla.gnome.org/show_bug.cgi?id=684742
        double dim_red = (rgba.red >= 0.5) ? -amount : amount;
        double dim_green = (rgba.green >= 0.5) ? -amount : amount;
        double dim_blue = (rgba.blue >= 0.5) ? -amount : amount;
        
        return Gdk.RGBA() {
            red = (rgba.red + dim_red).clamp(0.0, 1.0),
            green = (rgba.green + dim_green).clamp(0.0, 1.0),
            blue = (rgba.blue + dim_blue).clamp(0.0, 1.0),
            alpha = rgba.alpha
        };
    }
    
    private string rgba_to_markup(Gdk.RGBA rgba) {
        return "#%02x%02x%02x".printf(
            gdk_to_rgb(rgba.red), gdk_to_rgb(rgba.green), gdk_to_rgb(rgba.blue));
    }
    
    private Gdk.RGBA get_foreground_rgba(Gtk.Widget widget, bool selected) {
        return widget.get_style_context().get_color(selected ? Gtk.StateFlags.SELECTED : Gtk.StateFlags.NORMAL);
    }
    
    private string get_participants_markup(Gtk.Widget widget, bool selected) {
        if (conversation == null || account_owner_email == null)
            return "";
        
        string normalized_account_owner_email = account_owner_email.normalize().casefold();
        
        // Build chronological list of AuthorDisplay records, setting to unread if any message by
        // that author is unread
        Gee.ArrayList<ParticipantDisplay> list = new Gee.ArrayList<ParticipantDisplay>();
        foreach (Geary.Email message in conversation.get_emails(Geary.App.Conversation.Ordering.RECV_DATE_ASCENDING)) {
            // only display if something to display
            Geary.RFC822.MailboxAddresses? addresses = use_to ? message.to : message.from;
            if (addresses == null || addresses.size < 1)
                continue;
            
            foreach (Geary.RFC822.MailboxAddress address in addresses) {
                ParticipantDisplay participant_display = new ParticipantDisplay(address,
                    message.email_flags.is_unread());

                // if not present, add in chronological order
                int existing_index = list.index_of(participant_display);
                if (existing_index < 0) {
                    list.add(participant_display);

                    continue;
                }
                
                // if present and this message is unread but the prior were read,
                // this author is now unread
                if (message.email_flags.is_unread() && !list[existing_index].is_unread)
                    list[existing_index].is_unread = true;
            }
        }
        
        StringBuilder builder = new StringBuilder("<span foreground='%s'>".printf(
            rgba_to_markup(get_foreground_rgba(widget, selected))));
        if (list.size == 1) {
            // if only one participant, use full name
            builder.append(list[0].get_full_markup(normalized_account_owner_email));
        } else {
            bool first = true;
            foreach (ParticipantDisplay participant in list) {
                if (!first)
                    builder.append(", ");
                
                builder.append(participant.get_short_markup(normalized_account_owner_email));
                first = false;
            }
        }
        builder.append("</span>");
        
        return builder.str;
    }
    
    public void render(Cairo.Context ctx, Gtk.Widget widget, Gdk.Rectangle background_area, 
        Gdk.Rectangle cell_area, Gtk.CellRendererState flags, bool hover_select) {
        render_internal(widget, cell_area, ctx, flags, false, hover_select);
    }
    
    // Call this on style changes.
    public void calculate_sizes(Gtk.Widget widget) {
        render_internal(widget, null, null, 0, true, false);
    }
    
    // Must call calculate_sizes() first.
    public void get_size(Gtk.Widget widget, Gdk.Rectangle? cell_area, out int x_offset, 
        out int y_offset, out int width, out int height) {
        assert(cell_height != -1); // ensures calculate_sizes() was called.
        
        x_offset = 0;
        y_offset = 0;
        // set width to 1 (rather than 0) to work around certain themes that cause the
        // conversation list to be shown as "squished":
        // https://bugzilla.gnome.org/show_bug.cgi?id=713954
        width = 1;
        height = cell_height;
    }
    
    // Can be used for rendering or calculating height.
    private void render_internal(Gtk.Widget widget, Gdk.Rectangle? cell_area, 
        Cairo.Context? ctx, Gtk.CellRendererState flags, bool recalc_dims,
        bool hover_select) {
        bool display_preview = GearyApplication.instance.config.display_preview;
        int y = LINE_SPACING + (cell_area != null ? cell_area.y : 0);
        
        bool selected = (flags & Gtk.CellRendererState.SELECTED) != 0;
        bool hover = (flags & Gtk.CellRendererState.PRELIT) != 0 || (selected && hover_select);
        
        // Date field.
        Pango.Rectangle ink_rect = render_date(widget, cell_area, ctx, y, selected);

        // From field.
        ink_rect = render_from(widget, cell_area, ctx, y, selected, ink_rect);
        y += ink_rect.height + ink_rect.y + LINE_SPACING;

        // If we are displaying a preview then the message counter goes on the same line as the
        // preview, otherwise it is with the subject.
        int preview_height = 0;
        
        // Setup counter badge.
        count_badge.count = num_emails;
        int counter_width = count_badge.get_width(widget) + LINE_SPACING;
        int counter_x = cell_area != null ? cell_area.width - cell_area.x - counter_width +
            (LINE_SPACING / 2) : 0;
        
        if (display_preview) {
            // Subject field.
            render_subject(widget, cell_area, ctx, y, selected);
            y += ink_rect.height + ink_rect.y + LINE_SPACING;
            
            // Number of e-mails field.
            count_badge.render(widget, ctx, counter_x, y, selected);
            
            // Body preview.
            ink_rect = render_preview(widget, cell_area, ctx, y, selected, counter_width);
            preview_height = ink_rect.height + ink_rect.y + LINE_SPACING;
        } else {
            // Number of e-mails field.
            count_badge.render(widget, ctx, counter_x, y, selected);
            
            // Subject field.
            render_subject(widget, cell_area, ctx, y, selected, counter_width);
            y += ink_rect.height + ink_rect.y + LINE_SPACING;
        }
        
        // Draw separator line.
        if (ctx != null && cell_area != null) {
            ctx.set_line_width(1.0);
            GtkUtil.set_source_color_from_string(ctx, CountBadge.UNREAD_BG_COLOR);
            ctx.move_to(cell_area.x - 1, cell_area.y + cell_area.height);
            ctx.line_to(cell_area.x + cell_area.width + 1, cell_area.y + cell_area.height);
            ctx.stroke();
        }
        
        if (recalc_dims) {
            FormattedConversationData.preview_height = preview_height;
            FormattedConversationData.cell_height = y + preview_height;
        } else {
            int unread_y = display_preview ? cell_area.y + LINE_SPACING * 2 : cell_area.y +
                LINE_SPACING;
            
            // Unread indicator.
            if (is_unread || hover) {
                Gdk.Pixbuf read_icon = IconFactory.instance.load_symbolic(
                    is_unread ? "mail-unread-symbolic" : "mail-read-symbolic",
                    IconFactory.UNREAD_ICON_SIZE, widget.get_style_context());
                Gdk.cairo_set_source_pixbuf(ctx, read_icon, cell_area.x + LINE_SPACING, unread_y);
                ctx.paint();
            }
            
            // Starred indicator.
            if (is_flagged || hover) {
                int star_y = cell_area.y + (cell_area.height / 2) + (display_preview ? LINE_SPACING : 0);
                Gdk.Pixbuf starred_icon = IconFactory.instance.load_symbolic(
                    is_flagged ? "starred-symbolic" : "non-starred-symbolic",
                    IconFactory.STAR_ICON_SIZE, widget.get_style_context());
                Gdk.cairo_set_source_pixbuf(ctx, starred_icon, cell_area.x + LINE_SPACING, star_y);
                ctx.paint();
            }
        }
    }
    
    private Pango.Rectangle render_date(Gtk.Widget widget, Gdk.Rectangle? cell_area,
        Cairo.Context? ctx, int y, bool selected) {
        string date_markup = "<span foreground='%s'>%s</span>".printf(
            rgba_to_markup(dim_rgba(get_foreground_rgba(widget, selected), DIM_TEXT_AMOUNT)),
            Geary.HTML.escape_markup(date));
        
        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        Pango.FontDescription font_date = new Pango.FontDescription();
        font_date.set_size(FONT_SIZE_DATE * Pango.SCALE);
        Pango.Layout layout_date = widget.create_pango_layout(null);
        layout_date.set_font_description(font_date);
        layout_date.set_markup(date_markup, -1);
        layout_date.set_alignment(Pango.Alignment.RIGHT);
        layout_date.get_pixel_extents(out ink_rect, out logical_rect);
        if (ctx != null && cell_area != null) {
            ctx.move_to(cell_area.width - cell_area.x - ink_rect.width - ink_rect.x - LINE_SPACING, y);
            Pango.cairo_show_layout(ctx, layout_date);
        }
        return ink_rect;
    }
    
    private Pango.Rectangle render_from(Gtk.Widget widget, Gdk.Rectangle? cell_area,
        Cairo.Context? ctx, int y, bool selected, Pango.Rectangle ink_rect) {
        string from_markup = (conversation != null) ? get_participants_markup(widget, selected) : STYLE_EXAMPLE;
        
        Pango.FontDescription font_from = new Pango.FontDescription();
        font_from.set_size(FONT_SIZE_FROM * Pango.SCALE);
        Pango.Layout layout_from = widget.create_pango_layout(null);
        layout_from.set_font_description(font_from);
        layout_from.set_markup(from_markup, -1);
        layout_from.set_ellipsize(Pango.EllipsizeMode.END);
        if (ctx != null && cell_area != null) {
            layout_from.set_width((cell_area.width - ink_rect.width - ink_rect.x - (LINE_SPACING * 3) -
                TEXT_LEFT)
            * Pango.SCALE);
            ctx.move_to(cell_area.x + TEXT_LEFT, y);
            Pango.cairo_show_layout(ctx, layout_from);
        }
        return ink_rect;
    }
    
    private void render_subject(Gtk.Widget widget, Gdk.Rectangle? cell_area, Cairo.Context? ctx,
        int y, bool selected, int counter_width = 0) {
        string subject_markup = "<span foreground='%s'>%s</span>".printf(
            rgba_to_markup(dim_rgba(get_foreground_rgba(widget, selected), DIM_TEXT_AMOUNT)),
            Geary.HTML.escape_markup(subject));
        
        Pango.FontDescription font_subject = new Pango.FontDescription();
        font_subject.set_size(FONT_SIZE_SUBJECT * Pango.SCALE);
        if (is_unread)
            font_subject.set_weight(Pango.Weight.BOLD);
        Pango.Layout layout_subject = widget.create_pango_layout(null);
        layout_subject.set_font_description(font_subject);
        layout_subject.set_markup(subject_markup, -1);
        if (cell_area != null)
            layout_subject.set_width((cell_area.width - TEXT_LEFT - counter_width) * Pango.SCALE);
        layout_subject.set_ellipsize(Pango.EllipsizeMode.END);
        if (ctx != null && cell_area != null) {
            ctx.move_to(cell_area.x + TEXT_LEFT, y);
            Pango.cairo_show_layout(ctx, layout_subject);
        }
    }
    
    private Pango.Rectangle render_preview(Gtk.Widget widget, Gdk.Rectangle? cell_area,
        Cairo.Context? ctx, int y, bool selected, int counter_width = 0) {
        double dim = selected ? DIM_TEXT_AMOUNT : DIM_PREVIEW_TEXT_AMOUNT;
        string preview_markup = "<span foreground='%s'>%s</span>".printf(
            rgba_to_markup(dim_rgba(get_foreground_rgba(widget, selected), dim)),
            Geary.String.is_empty(body) ? "" : Geary.HTML.escape_markup(body));
        
        Pango.FontDescription font_preview = new Pango.FontDescription();
        font_preview.set_size(FONT_SIZE_PREVIEW * Pango.SCALE);
        
        Pango.Layout layout_preview = widget.create_pango_layout(null);
        layout_preview.set_font_description(font_preview);
        
        layout_preview.set_markup(preview_markup, -1);
        layout_preview.set_wrap(Pango.WrapMode.WORD);
        layout_preview.set_ellipsize(Pango.EllipsizeMode.END);
        if (ctx != null && cell_area != null) {
            layout_preview.set_width((cell_area.width - TEXT_LEFT - counter_width - LINE_SPACING) * Pango.SCALE);
            layout_preview.set_height(preview_height * Pango.SCALE);
            
            ctx.move_to(cell_area.x + TEXT_LEFT, y);
            Pango.cairo_show_layout(ctx, layout_preview);
        } else {
            layout_preview.set_width(int.MAX);
            layout_preview.set_height(int.MAX);
        }

        Pango.Rectangle? ink_rect;
        Pango.Rectangle? logical_rect;
        layout_preview.get_pixel_extents(out ink_rect, out logical_rect);
        return ink_rect;
    }
    
}

