/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an {@link Geary.RFC822.Message}.
 *
 * This view corresponds to {@link Geary.RFC822.Message}, displaying
 * both the message's headers and body. Any attachments and sub
 * messages are handled by {@link ConversationEmail}, which typically
 * embeds at least one instance of this class.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-message.ui")]
public class ConversationMessage : Gtk.Grid {


    private const string FROM_CLASS = "geary-from";
    private const string REPLACED_CID_TEMPLATE = "replaced_%02u@geary";
    private const string REPLACED_IMAGE_CLASS = "geary_replaced_inline_image";

    private const int MAX_PREVIEW_BYTES = Geary.Email.MAX_PREVIEW_BYTES;


    internal static inline bool has_distinct_name(
        Geary.RFC822.MailboxAddress address) {
        return (
            !Geary.String.is_empty(address.name) &&
            address.name != address.address
        );
    }


    // Widget used to display sender/recipient email addresses in
    // message header Gtk.FlowBox instances.
    private class AddressFlowBoxChild : Gtk.FlowBoxChild {

        private const string PRIMARY_CLASS = "geary-primary";
        private const string MATCH_CLASS = "geary-match";

        public enum Type { FROM, OTHER; }

        public Geary.RFC822.MailboxAddress address { get; private set; }

        private string search_value;

        public AddressFlowBoxChild(Geary.RFC822.MailboxAddress address,
                                   Type type = Type.OTHER) {
            this.address = address;
            this.search_value = address.address.casefold();

            // We use two label instances here when address has
            // distinct parts so we can dim the secondary part, if
            // any. Ideally, it would be just one label instance in
            // both cases, but we can't yet include CSS classes in
            // Pango markup. See Bug 766763.

            Gtk.Grid address_parts = new Gtk.Grid();

            Gtk.Label primary = new Gtk.Label(null);
            primary.ellipsize = Pango.EllipsizeMode.END;
            GtkUtil.set_label_xalign(primary, 0.0f);
            primary.get_style_context().add_class(PRIMARY_CLASS);
            if (type == Type.FROM) {
                primary.get_style_context().add_class(FROM_CLASS);
            }
            address_parts.add(primary);

            if (has_distinct_name(address)) {
                primary.set_text(address.name);

                Gtk.Label secondary = new Gtk.Label(null);
                secondary.ellipsize = Pango.EllipsizeMode.END;
                GtkUtil.set_label_xalign(secondary, 0.0f);
                secondary.get_style_context().add_class(Gtk.STYLE_CLASS_DIM_LABEL);
                secondary.set_text(address.address);
                address_parts.add(secondary);

                this.search_value = address.name.casefold() + this.search_value;
            } else {
                primary.set_text(address.address);
            }

            // Update prelight state when mouse-overed.
            Gtk.EventBox events = new Gtk.EventBox();
            events.add_events(
                Gdk.EventMask.ENTER_NOTIFY_MASK |
                Gdk.EventMask.LEAVE_NOTIFY_MASK
            );
            events.set_visible_window(false);
            events.enter_notify_event.connect(on_prelight_in_event);
            events.leave_notify_event.connect(on_prelight_out_event);
            events.add(address_parts);

            add(events);
            set_halign(Gtk.Align.START);
            show_all();
        }

        public bool highlight_search_term(string term) {
            bool found = this.search_value.contains(term);
            if (found) {
                get_style_context().add_class(MATCH_CLASS);
            } else {
                get_style_context().remove_class(MATCH_CLASS);
            }
            return found;
        }

        public void unmark_search_terms() {
            get_style_context().remove_class(MATCH_CLASS);
        }

        private bool on_prelight_in_event(Gdk.Event event) {
            set_state_flags(Gtk.StateFlags.PRELIGHT, false);
            return Gdk.EVENT_STOP;
        }

        private bool on_prelight_out_event(Gdk.Event event) {
            unset_state_flags(Gtk.StateFlags.PRELIGHT);
            return Gdk.EVENT_STOP;
        }

    }

    private const string[] INLINE_MIME_TYPES = {
        "image/png",
        "image/gif",
        "image/jpeg",
        "image/pjpeg",
        "image/bmp",
        "image/x-icon",
        "image/x-xbitmap",
        "image/x-xbm"
    };

    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;

    private const string ACTION_COPY_EMAIL = "copy_email";
    private const string ACTION_COPY_LINK = "copy_link";
    private const string ACTION_COPY_SELECTION = "copy_selection";
    private const string ACTION_OPEN_INSPECTOR = "open_inspector";
    private const string ACTION_OPEN_LINK = "open_link";
    private const string ACTION_SAVE_IMAGE = "save_image";
    private const string ACTION_SEARCH_FROM = "search_from";
    private const string ACTION_SELECT_ALL = "select_all";


    /** The specific RFC822 message displayed by this view. */
    public Geary.RFC822.Message message { get; private set; }

    /** Box containing the preview and full header widgets.  */
    [GtkChild]
    internal Gtk.Grid summary;

    /** Box that InfoBar widgets should be added to. */
    [GtkChild]
    internal Gtk.Grid infobars;

    /** HTML view that displays the message body. */
    internal ConversationWebView web_view { get; private set; }

    [GtkChild]
    private Gtk.Image avatar;

    [GtkChild]
    private Gtk.Revealer preview_revealer;
    [GtkChild]
    private Gtk.Label preview_from;
    [GtkChild]
    private Gtk.Label preview_date;
    [GtkChild]
    private Gtk.Label preview_body;

    [GtkChild]
    private Gtk.Revealer header_revealer;
    [GtkChild]
    private Gtk.FlowBox from;
    [GtkChild]
    private Gtk.Label subject;
    [GtkChild]
    private Gtk.Label date;

    [GtkChild]
    private Gtk.Grid sender_header;
    [GtkChild]
    private Gtk.FlowBox sender_address;

    [GtkChild]
    private Gtk.Grid reply_to_header;
    [GtkChild]
    private Gtk.FlowBox reply_to_addresses;

    [GtkChild]
    private Gtk.Grid to_header;
    [GtkChild]
    private Gtk.Grid cc_header;
    [GtkChild]
    private Gtk.Grid bcc_header;

    [GtkChild]
    private Gtk.Revealer body_revealer;
    [GtkChild]
    public Gtk.Box body; // WebKit.WebView crashes when added to a Grid

    [GtkChild]
    private Gtk.Popover link_popover;
    //[GtkChild]
    //private Gtk.Label good_link_label;
    //[GtkChild]
    //private Gtk.Label bad_link_label;

    [GtkChild]
    private Gtk.InfoBar remote_images_infobar;

    // The web_view's context menu
    private Gtk.Menu? context_menu = null;

    // Menu models for creating the context menu
    private MenuModel context_menu_link;
    private MenuModel context_menu_email;
    private MenuModel context_menu_image;
    private MenuModel context_menu_main;
    private MenuModel context_menu_contact;
    private MenuModel? context_menu_inspector = null;

    // Address fields that can be search through
    private Gee.List<AddressFlowBoxChild> searchable_addresses =
        new Gee.LinkedList<AddressFlowBoxChild>();

    // Resource that have been loaded by the web view
    private Gee.Map<string,WebKit.WebResource> resources =
        new Gee.HashMap<string,WebKit.WebResource>();

    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    private int next_replaced_buffer_number = 0;


    /** Fired when the user clicks a link in the email. */
    public signal void link_activated(string link);

    /** Fired when the user requests remote images be loaded. */
    public signal void flag_remote_images();

    /** Fired when the user requests remote images be always loaded. */
    public signal void remember_remote_images();

    /** Fired when the user saves an inline displayed image. */
    public signal void save_image(string? filename, Geary.Memory.Buffer buffer);

    /** Fired when the user activates a specific search shortcut. */
    public signal void search_activated(string operator, string value);


    /**
     * Constructs a new view to display an RFC 823 message headers and body.
     *
     * This method sets up most of the user interface for displaying
     * the message, but does not attempt any possibly long-running
     * loading processes.
     */
    public ConversationMessage(Geary.RFC822.Message message,
                               bool load_remote_images) {
        this.message = message;

#if !GTK_3_20
        // GTK < 3.20+ style workarounds. Keep this in sync with
        // geary.css.
        this.summary.border_width = 12;
#endif

        // Actions

        add_action(ACTION_COPY_EMAIL, true, VariantType.STRING)
            .activate.connect(on_copy_email_address);
        add_action(ACTION_COPY_LINK, true, VariantType.STRING)
            .activate.connect(on_copy_link);
        add_action(ACTION_COPY_SELECTION, false).activate.connect(() => {
                web_view.copy_clipboard();
            });
        add_action(ACTION_OPEN_INSPECTOR, Args.inspector).activate.connect(() => {
                this.web_view.get_inspector().show();
            });
        add_action(ACTION_OPEN_LINK, true, VariantType.STRING)
            .activate.connect((param) => {
                link_activated(param.get_string());
            });
        add_action(ACTION_SAVE_IMAGE, true, VariantType.STRING)
            .activate.connect(on_save_image);
        add_action(ACTION_SEARCH_FROM, true, VariantType.STRING)
            .activate.connect((param) => {
                search_activated("from", param.get_string());
            });
        add_action(ACTION_SELECT_ALL, true).activate.connect(() => {
                web_view.select_all();
            });

        insert_action_group("msg", message_actions);

        // Context menu

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menus.ui"
        );
        context_menu_link = (MenuModel) builder.get_object("context_menu_link");
        context_menu_email = (MenuModel) builder.get_object("context_menu_email");
        context_menu_image = (MenuModel) builder.get_object("context_menu_image");
        context_menu_main = (MenuModel) builder.get_object("context_menu_main");
        context_menu_contact = (MenuModel) builder.get_object("context_menu_contact");
        if (Args.inspector) {
            context_menu_inspector =
                (MenuModel) builder.get_object("context_menu_inspector");
        }

        // Preview headers

        // Translators: This is displayed in place of the from address
        // when the message has no from address.
        string empty_from = _("No sender");

        this.preview_from.set_text(format_originator_preview(empty_from));
        this.preview_from.get_style_context().add_class(FROM_CLASS);

        string date_text = "";
        string date_tooltip = "";
        if (this.message.date != null) {
            Date.ClockFormat clock_format =
                GearyApplication.instance.config.clock_format;
            date_text = Date.pretty_print(
                this.message.date.value, clock_format
            );
            date_tooltip = Date.pretty_print_verbose(
                this.message.date.value, clock_format
            );
        }
        this.preview_date.set_text(date_text);
        this.preview_date.set_tooltip_text(date_tooltip);

        string preview = this.message.get_preview();
        if (preview.length > MAX_PREVIEW_BYTES) {
            preview = Geary.String.safe_byte_substring(preview, MAX_PREVIEW_BYTES);
            // Add an ellipsis in case the wider is wider than the text
            preview += "…";
        }
        this.preview_body.set_text(preview);

        // Full headers

        fill_originator_addresses(empty_from);

        this.date.set_text(date_text);
        this.date.set_tooltip_text(date_tooltip);
        if (this.message.subject != null) {
            this.subject.set_text(this.message.subject.value);
            this.subject.set_visible(true);
        }
        fill_header_addresses(this.to_header, this.message.to);
        fill_header_addresses(this.cc_header, this.message.cc);
        fill_header_addresses(this.bcc_header, this.message.bcc);

        // Web view

        this.web_view = new ConversationWebView();
        if (load_remote_images) {
            this.web_view.allow_remote_image_loading();
        }
        this.web_view.context_menu.connect(on_context_menu);
        this.web_view.link_activated.connect((link) => {
                link_activated(link);
            });
        this.web_view.mouse_target_changed.connect(on_mouse_target_changed);
        this.web_view.resource_load_started.connect((view, res, req) => {
                this.resources[res.get_uri()] = res;
            });
        this.web_view.remote_image_load_blocked.connect(() => {
                this.remote_images_infobar.show();
            });
        this.web_view.selection_changed.connect(on_selection_changed);
        this.web_view.show();

        this.body.set_has_tooltip(true); // Used to show link URLs
        this.body.pack_start(this.web_view, true, true, 0);
    }

    public override void destroy() {
        this.resources.clear();
        this.searchable_addresses.clear();
        base.destroy();
    }

    /**
     * Shows the complete message and hides the preview headers.
     */
    public void show_message_body(bool include_transitions=true) {
        set_revealer(this.preview_revealer, false, include_transitions);
        set_revealer(this.header_revealer, true, include_transitions);
        set_revealer(this.body_revealer, true, include_transitions);
    }

    /**
     * Hides the complete message and shows the preview headers.
     */
    public void hide_message_body() {
        preview_revealer.set_reveal_child(true);
        header_revealer.set_reveal_child(false);
        body_revealer.set_reveal_child(false);
    }

    /**
     * Starts loading the avatar for the message's sender.
     */
    public async void load_avatar(Soup.Session session, Cancellable load_cancelled) {
        Geary.RFC822.MailboxAddress? primary = message.get_primary_originator();
        if (primary != null) {
            int window_scale = get_scale_factor();
            int pixel_size = this.avatar.get_pixel_size();
            Soup.Message message = new Soup.Message(
                "GET",
                Gravatar.get_image_uri(
                    primary, Gravatar.Default.NOT_FOUND, pixel_size * window_scale
                )
            );

            try {
                InputStream data =
                    yield session.send_async(message, load_cancelled);
                if (data != null && message.status_code == 200) {
                    yield set_avatar(data, load_cancelled);
                }
            } catch (Error err) {
                debug("Error loading Gravatar response: %s", err.message);
            }
        }
    }

    /**
     * Starts loading the message body in the HTML view.
     */
    public async void load_message_body(Cancellable load_cancelled) {
        string? body_text = null;
        try {
            body_text = (this.message.has_html_body())
                ? this.message.get_html_body(inline_image_replacer)
                : this.message.get_plain_body(true, inline_image_replacer);
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }

        load_cancelled.cancelled.connect(() => { web_view.stop_loading(); });
        // XXX Hook up unset_controllable_quotes() to size_allocate
        // and check is_height_valid since we need to accurately know
        // what the sizes of the quote and its container is to
        // determine if it should be unhidden. However this means that
        // when the user expands a hidden quote, this handler gets
        // executed again and since the expanded quote will meet the
        // criteria for being unset as controllable, that will
        // happen. That's actually okay for now though, because if the
        // user could collapse the quote again the space wouldn't be
        // reclaimed, which is worse than this.
        this.web_view.size_allocate.connect(() => {
                if (this.web_view.is_loaded &&
                    this.web_view.is_height_valid) {
                    this.web_view.unset_controllable_quotes();
                }
            });

        this.web_view.clean_and_load(body_text ?? "");
    }

    /**
     * Highlights user search terms in the message view.
     &
     * Returns the number of matching search terms.
     */
    public uint highlight_search_terms(Gee.Set<string> search_matches) {
        // Remove existing highlights
        this.web_view.get_find_controller().search_finish();

        uint headers_found = 0;
        uint webkit_found = 0;
        foreach(string raw_match in search_matches) {
            string match = raw_match.casefold();

            debug("Matching: %s", match);

            foreach (AddressFlowBoxChild address in this.searchable_addresses) {
                if (address.highlight_search_term(match)) {
                    ++headers_found;
                }
            }

            //webkit_found += this.web_view.mark_text_matches(raw_match, false, 0);
            this.web_view.get_find_controller().search(
                raw_match,
                WebKit.FindOptions.CASE_INSENSITIVE,
                1024
            );
        }

        return headers_found + webkit_found;
    }

    /**
     * Disables highlighting of any search terms in the message view.
     */
    public void unmark_search_terms() {
        foreach (AddressFlowBoxChild address in this.searchable_addresses) {
            address.unmark_search_terms();
        }
        web_view.get_find_controller().search_finish();
    }

    internal string? get_selection_for_quoting() {
        return this.web_view.get_selection_for_quoting();
    }

    /**
     * Returns the current selection as a string, suitable for find.
     */
    internal string? get_selection_for_find() {
        return this.web_view.get_selection_for_find();
    }

    private SimpleAction add_action(string name, bool enabled, VariantType? type = null) {
        SimpleAction action = new SimpleAction(name, type);
        action.set_enabled(enabled);
        message_actions.add_action(action);
        return action;
    }

    private void set_action_enabled(string name, bool enabled) {
        SimpleAction? action = this.message_actions.lookup(name) as SimpleAction;
        if (action != null) {
            action.set_enabled(enabled);
        }
    }

    private Menu set_action_param_string(MenuModel existing, string value) {
        Menu menu = new Menu();
        for (int i = 0; i < existing.get_n_items(); i++) {
            MenuItem item = new MenuItem.from_model(existing, i);
            Variant action = item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            item.set_action_and_target(
                action.get_string(),
                VariantType.STRING.dup_string(),
                value
            );
            menu.append_item(item);
        }
        return menu;
    }

    private Menu set_action_param_strings(MenuModel existing,
                                          Gee.Map<string,string> values) {
        Menu menu = new Menu();
        for (int i = 0; i < existing.get_n_items(); i++) {
            MenuItem item = new MenuItem.from_model(existing, i);
            Variant action = item.get_attribute_value(
                Menu.ATTRIBUTE_ACTION, VariantType.STRING
            );
            string fq_name = action.get_string();
            string name = fq_name.substring(fq_name.index_of(".") + 1);
            item.set_action_and_target(
                fq_name, VariantType.STRING.dup_string(), values[name]
            );
            menu.append_item(item);
        }
        return menu;
    }

    private string format_originator_preview(string empty_from_text) {
        string text = "";
        if (this.message.from != null && this.message.from.size > 0) {
            int i = 0;
            Gee.List<Geary.RFC822.MailboxAddress> list =
                this.message.from.get_all();
            foreach (Geary.RFC822.MailboxAddress addr in list) {
                text += has_distinct_name(addr) ? addr.name : addr.address;

                if (++i < list.size)
                    // Translators: This separates multiple 'from'
                    // addresses in the header preview for a message.
                    text += _(", ");
            }
        } else {
            text = empty_from_text;
        }

        return text;
    }

    private void fill_originator_addresses(string empty_from_text)  {
        // Show any From header addresses
        if (this.message.from != null && this.message.from.size > 0) {
            foreach (Geary.RFC822.MailboxAddress address in this.message.from) {
                AddressFlowBoxChild child = new AddressFlowBoxChild(
                    address, AddressFlowBoxChild.Type.FROM
                );
                this.searchable_addresses.add(child);
                this.from.add(child);
            }
        } else {
            Gtk.Label label = new Gtk.Label(null);
            label.set_text(empty_from_text);

            Gtk.FlowBoxChild child = new Gtk.FlowBoxChild();
            child.add(label);
            child.set_halign(Gtk.Align.START);
            child.show_all();
            this.from.add(child);
        }

        // Show the Sender header addresses if present, but only if
        // not already in the From header.
        if (this.message.sender != null &&
            (this.message.from == null ||
             !this.message.from.contains_normalized(this.message.sender.address))) {
            AddressFlowBoxChild child = new AddressFlowBoxChild(this.message.sender);
            this.searchable_addresses.add(child);
            this.sender_header.show();
            this.sender_address.add(child);
        }

        // Show any Reply-To header addresses if present, but only if
        // each is not already in the From header.
        if (this.message.reply_to != null) {
            foreach (Geary.RFC822.MailboxAddress address in this.message.reply_to) {
                if (this.message.from == null ||
                    !this.message.from.contains_normalized(address.address)) {
                    AddressFlowBoxChild child = new AddressFlowBoxChild(address);
                    this.searchable_addresses.add(child);
                    this.reply_to_addresses.add(child);
                    this.reply_to_header.show();
                }
            }
        }
    }

    private void fill_header_addresses(Gtk.Grid header,
                                       Geary.RFC822.MailboxAddresses? addresses) {
        if (addresses != null && addresses.size > 0) {
            Gtk.FlowBox box = header.get_children().nth(0).data as Gtk.FlowBox;
            if (box != null) {
                foreach (Geary.RFC822.MailboxAddress address in addresses) {
                    AddressFlowBoxChild child = new AddressFlowBoxChild(address);
                    this.searchable_addresses.add(child);
                    box.add(child);
                }
            }
            header.set_visible(true);
        }
    }

    private async void set_avatar(InputStream data,
                                  Cancellable load_cancelled)
    throws Error {
        Gdk.Pixbuf avatar_buf =
            yield Gdk.Pixbuf.new_from_stream_async(data, load_cancelled);

        if (avatar_buf != null && !load_cancelled.is_cancelled()) {
            int window_scale = get_scale_factor();
            int avatar_size = this.avatar.pixel_size * window_scale;
            if (avatar_buf.width != avatar_size) {
                avatar_buf = avatar_buf.scale_simple(
                    avatar_size, avatar_size, Gdk.InterpType.BILINEAR
                );
            }
            this.avatar.set_from_surface(
                Gdk.cairo_surface_create_from_pixbuf(
                    avatar_buf, window_scale, get_window()
                )
            );
        }
    }

    // This delegate is called from within Geary.RFC822.Message.get_body while assembling the plain
    // or HTML document when a non-text MIME part is encountered within a multipart/mixed container.
    // If this returns null, the MIME part is dropped from the final returned document; otherwise,
    // this returns HTML that is placed into the document in the position where the MIME part was
    // found
    private string? inline_image_replacer(string filename, Geary.Mime.ContentType? content_type,
        Geary.Mime.ContentDisposition? disposition, string? content_id, Geary.Memory.Buffer buffer) {
        if (content_type == null) {
            debug("Not displaying inline: no Content-Type");
            return null;
        }

        bool is_supported = false;
        foreach (string mime_type in INLINE_MIME_TYPES) {
            try {
                is_supported = content_type.is_mime_type(mime_type);
            } catch (Error err) {
                debug("Unable to compare MIME type %s: %s", mime_type, err.message);
            }
            if (is_supported) {
                break;
            }
        }

        if (!is_supported) {
            debug("Not displaying %s inline: unsupported Content-Type", content_type.to_string());
            return null;
        }

        string id = content_id;
        if (id == null) {
            id = REPLACED_CID_TEMPLATE.printf(this.next_replaced_buffer_number++);
        }

        this.web_view.add_inline_resource(id, buffer);

        return "<img alt=\"%s\" class=\"%s\" src=\"%s%s\" />".printf(
            Geary.HTML.escape_markup(filename),
            REPLACED_IMAGE_CLASS,
            ClientWebView.CID_PREFIX,
            Geary.HTML.escape_markup(id)
        );
    }

    private void show_images(bool remember) {
        this.web_view.load_remote_images();
        if (remember) {
            flag_remote_images();
        }
    }

    /*
     * Test whether text looks like a URI that leads somewhere other than href.  The text
     * will have a scheme prepended if it doesn't already have one, and the short versions
     * have the scheme skipped and long paths truncated.
     */
    // private bool deceptive_text(string href, ref string text, out string href_short,
    //     out string text_short) {
    //     href_short = "";
    //     text_short = "";
    //     // mailto URLs have a different form, and the worst they can do is pop up a composer,
    //     // so we don't trigger on them.
    //     if (href.has_prefix("mailto:"))
    //         return false;
        
    //     // First, does text look like a URI?  Right now, just test whether it has
    //     // <string>.<string> in it.  More sophisticated tests are possible.
    //     GLib.MatchInfo text_match, href_match;
    //     try {
    //         GLib.Regex domain = new GLib.Regex(
    //             "([a-z]*://)?"                  // Optional scheme
    //             + "([^\\s:/]+\\.[^\\s:/\\.]+)"  // Domain
    //             + "(/[^\\s]*)?"                 // Optional path
    //             );
    //         if (!domain.match(text, 0, out text_match))
    //             return false;
    //         if (!domain.match(href, 0, out href_match)) {
    //             // If href doesn't look like a URL, something is fishy, so warn the user
    //             href_short = href + _(" (Invalid?)");
    //             text_short = text;
    //             return true;
    //         }
    //     } catch (Error error) {
    //         warning("Error in Regex text for deceptive urls: %s", error.message);
    //         return false;
    //     }
        
    //     // Second, do the top levels of the two domains match?  We compare the top n levels,
    //     // where n is the minimum of the number of levels of the two domains.
    //     string[] href_parts = href_match.fetch_all();
    //     string[] text_parts = text_match.fetch_all();
    //     string[] text_domain = text_parts[2].down().reverse().split(".");
    //     string[] href_domain = href_parts[2].down().reverse().split(".");
    //     for (int i = 0; i < text_domain.length && i < href_domain.length; i++) {
    //         if (text_domain[i] != href_domain[i]) {
    //             if (href_parts[1] == "")
    //                 href_parts[1] = "http://";
    //             if (text_parts[1] == "")
    //                 text_parts[1] = href_parts[1];
    //             string temp;
    //             assemble_uris(href_parts, out temp, out href_short);
    //             assemble_uris(text_parts, out text, out text_short);
    //             return true;
    //         }
    //     }
    //     return false;
    // }

    // private void assemble_uris(string[] parts, out string full, out string short_) {
    //     full = parts[1] + parts[2];
    //     short_ = parts[2];
    //     if (parts.length == 4 && parts[3] != "/") {
    //         full += parts[3];
    //         if (parts[3].length > 20)
    //             short_ += parts[3].substring(0, 20) + "…";
    //         else
    //             short_ += parts[3];
    //     }
    // }

    private inline void set_revealer(Gtk.Revealer revealer,
                                     bool expand,
                                     bool use_transition) {
        Gtk.RevealerTransitionType transition = revealer.get_transition_type();
        if (!use_transition) {
            revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        revealer.set_reveal_child(expand);
        revealer.set_transition_type(transition);
    }

    [GtkCallback]
    private void on_address_box_child_activated(Gtk.FlowBox box,
                                                Gtk.FlowBoxChild child) {
        AddressFlowBoxChild address_child = child as AddressFlowBoxChild;
        if (address_child != null) {
            address_child.set_state_flags(Gtk.StateFlags.ACTIVE, false);

            Geary.RFC822.MailboxAddress address = address_child.address;
            Gee.Map<string,string> values = new Gee.HashMap<string,string>();
            values[ACTION_OPEN_LINK] =
                Geary.ComposedEmail.MAILTO_SCHEME + address.address;
            values[ACTION_COPY_EMAIL] = address.get_full_address();
            values[ACTION_SEARCH_FROM] = address.address;

            Menu model = new Menu();
            model.append_section(
                null, set_action_param_strings(this.context_menu_email, values)
            );
            model.append_section(
                null, set_action_param_strings(this.context_menu_contact, values)
            );
            Gtk.Popover popover = new Gtk.Popover.from_model(child, model);
            popover.set_position(Gtk.PositionType.BOTTOM);
            popover.closed.connect(() => {
                    address_child.unset_state_flags(Gtk.StateFlags.ACTIVE);
                });
            popover.show();
        }
    }

    private bool on_context_menu(WebKit.WebView view,
                                 WebKit.ContextMenu context_menu,
                                 Gdk.Event event,
                                 WebKit.HitTestResult hit_test) {
        if (this.context_menu != null) {
            this.context_menu.detach();
        }

        // Build a new context menu every time the user clicks because
        // at the moment under GTK+3.20 it's far easier to selectively
        // build a new menu model from pieces as we do here, then to
        // have a single menu model and disable the parts we don't
        // need.
        Menu model = new Menu();

        if (hit_test.context_is_link()) {
            string link_url = hit_test.get_link_uri();
            MenuModel link_menu =
                link_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)
                ? context_menu_email
                : context_menu_link;
            model.append_section(
                null, set_action_param_string(link_menu, link_url)
            );
        }

        if (hit_test.context_is_image()) {
            string uri = hit_test.get_image_uri();
            set_action_enabled(ACTION_SAVE_IMAGE, uri in this.resources);
            model.append_section(
                null, set_action_param_string(context_menu_image, uri)
            );
        }

        model.append_section(null, context_menu_main);

        if (context_menu_inspector != null) {
            model.append_section(null, context_menu_inspector);
        }

        this.context_menu = new Gtk.Menu.from_model(model);
        this.context_menu.attach_to_widget(this, null);
        this.context_menu.popup(null, null, null, 0, event.get_time());

        return true;
    }

    private void on_mouse_target_changed(WebKit.WebView web_view,
                                         WebKit.HitTestResult hit_test,
                                         uint modifiers) {
        if (hit_test.context_is_link()) {
            this.body.set_tooltip_text(hit_test.get_link_uri());
            this.body.trigger_tooltip_query();
        }
    }

    // // Check for possible phishing links, displays a popover if found.
    // // If not, lets it go through to the default handler.
    // private bool on_link_clicked() {
    //     string? href = element.get_attribute("href");
    //     if (Geary.String.is_empty(href))
    //         return false;
    //     string text = ((WebKit.DOM.HTMLElement) element).get_inner_text();
    //     string href_short, text_short;
    //     if (!deceptive_text(href, ref text, out href_short, out text_short))
    //         return false;

    //     Escape text and especially URLs since we got them from the
    //     HREF, and Gtk.Label.set_markup is a strict parser.
    //     good_link_label.set_markup(
    //         Markup.printf_escaped("<a href=\"%s\">%s</a>", text, text_short)
    //     );
    //     bad_link_label.set_markup(
    //         Markup.printf_escaped("<a href=\"%s\">%s</a>", href, href_short)
    //     );

    //     Work out the link's position, update the popover.
    //     Gdk.Rectangle link_rect = Gdk.Rectangle();
    //     web_view.get_allocation(out link_rect);
    //     WebKit.DOM.Element? offset_parent = element;
    //     while (offset_parent != null) {
    //         link_rect.x += (int) offset_parent.offset_left;
    //         link_rect.y += (int) offset_parent.offset_top;
    //         offset_parent = offset_parent.offset_parent;
    //     }
    //     link_rect.width = (int) element.offset_width;
    //     link_rect.height = (int) element.offset_height;
    //     link_popover.set_pointing_to(link_rect);

    //     link_popover.show();
    //     return true;
    // }

    [GtkCallback]
    private bool on_link_popover_activated() {
        this.link_popover.hide();
        return Gdk.EVENT_PROPAGATE;
    }

    private void on_selection_changed(bool has_selection) {
        set_action_enabled(ACTION_COPY_SELECTION, has_selection);
    }

    [GtkCallback]
    private void on_remote_images_response(Gtk.InfoBar info_bar, int response_id) {
        switch (response_id) {
        case 1:
            // Show images for the message
            show_images(true);
            break;
        case 2:
            // Show images for sender
            show_images(false);
            remember_remote_images();
            break;
        default:
            // Pass
            break;
        }

        remote_images_infobar.hide();
    }

    private void on_copy_link(Variant? param) {
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(param.get_string(), -1);
        clipboard.store();
    }

    private void on_copy_email_address(Variant? param) {
        string value = param.get_string();
        if (value.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            value = value.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1);
        }
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(value, -1);
        clipboard.store();
    }

    private void on_save_image(Variant? param) {
        WebKit.WebResource response = this.resources.get(param.get_string());
        response.get_data.begin(null, (obj, res) => {
                try {
                    uint8[] data = response.get_data.end(res);
                    save_image(response.get_uri(),
                               new Geary.Memory.ByteBuffer(data, data.length));
                } catch (Error err) {
                    debug(
                        "Failed to get image data from web view: %s",
                        err.message
                    );
                }
            });
    }

}
