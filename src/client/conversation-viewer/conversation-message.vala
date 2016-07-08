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
public class ConversationMessage : Gtk.Box {

    // Internal class to associate inline image buffers (replaced by
    // rotated scaled versions of them) so they can be saved intact if
    // the user requires it
    private class ReplacedImage : Geary.BaseObject {
        public string id;
        public string filename;
        public Geary.Memory.Buffer buffer;

        public ReplacedImage(int replaced_number, string filename, Geary.Memory.Buffer buffer) {
            id = "%X".printf(replaced_number);
            this.filename = filename;
            this.buffer = buffer;
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
    private const string REPLACED_IMAGE_CLASS = "replaced_inline_image";
    private const string DATA_IMAGE_CLASS = "data_inline_image";
    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;
    private const int QUOTE_SIZE_THRESHOLD = 120;

    private const string ACTION_COPY_EMAIL = "copy_email";
    private const string ACTION_COPY_LINK = "copy_link";
    private const string ACTION_COPY_SELECTION = "copy_selection";
    private const string ACTION_OPEN_INSPECTOR = "open_inspector";
    private const string ACTION_OPEN_LINK = "open_link";
    private const string ACTION_SAVE_IMAGE = "save_image";
    private const string ACTION_SELECT_ALL = "select_all";


    /** The specific RFC822 message displayed by this view. */
    public Geary.RFC822.Message message { get; private set; }

    /** Current allocated size of the HTML body view. */
    public Gdk.Rectangle web_view_allocation { get; private set; }

    /** Specifies if the message body been been fully loaded. */
    public bool is_loading_complete = false;

    /** Box containing the preview and full header widgets.  */
    [GtkChild]
    internal Gtk.Box summary_box;

    /** Box that InfoBar widgets should be added to. */
    [GtkChild]
    internal Gtk.Box infobar_box;

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
    private Gtk.Box to_header;
    [GtkChild]
    private Gtk.Box cc_header;
    [GtkChild]
    private Gtk.Box bcc_header;

    [GtkChild]
    private Gtk.Revealer body_revealer;
    [GtkChild]
    public Gtk.Box body_box;

    [GtkChild]
    private Gtk.Popover link_popover;
    [GtkChild]
    private Gtk.Label good_link_label;
    [GtkChild]
    private Gtk.Label bad_link_label;

    [GtkChild]
    private Gtk.InfoBar remote_images_infobar;

    // The web_view's context menu
    private Gtk.Menu? context_menu = null;

    // Menu models for creating the context menu
    private MenuModel context_menu_link;
    private MenuModel context_menu_email;
    private MenuModel context_menu_image;
    private MenuModel context_menu_main;
    private MenuModel? context_menu_inspector = null;

    // Last known DOM element under the context menu
    private WebKit.DOM.HTMLElement? context_menu_element = null;

    // Contains the current mouse-over'ed link URL, if any
    private string? hover_url = null;

    // The contacts for the message's account
    private Geary.ContactStore contact_store;

    // Should any remote messages be always loaded and displayed?
    private bool always_load_remote_images;

    private int next_replaced_buffer_number = 0;
    private Gee.HashMap<string, ReplacedImage> replaced_images = new Gee.HashMap<string, ReplacedImage>();
    private Gee.HashSet<string> replaced_content_ids = new Gee.HashSet<string>();


    // Message-specific actions
    private SimpleActionGroup message_actions = new SimpleActionGroup();

    /** Fired when an attachment is added for inline display. */
    public signal void attachment_displayed_inline(string id);

    /** Fired when the user requests remote images be loaded. */
    public signal void flag_remote_images();

    /** Fired when the user requests remote images be always loaded. */
    public signal void remember_remote_images();

    /** Fired when the user saves an inline displayed image. */
    public signal void save_image(string? filename, Geary.Memory.Buffer buffer);


    /**
     * Constructs a new view to display an RFC 823 message headers and body.
     *
     * This method sets up most of the user interface for displaying
     * the message, but does not attempt any possibly long-running
     * loading processes.
     */
    public ConversationMessage(Geary.RFC822.Message message,
                               Geary.ContactStore contact_store,
                               bool always_load_remote_images) {
        this.message = message;
        this.contact_store = contact_store;
        this.always_load_remote_images = always_load_remote_images;

        // Actions

        add_action(ACTION_COPY_EMAIL, false).activate.connect(on_copy_email_address);
        add_action(ACTION_COPY_LINK, false).activate.connect(on_copy_link);
        add_action(ACTION_COPY_SELECTION, false).activate.connect(() => {
                web_view.copy_clipboard();
            });
        add_action(ACTION_OPEN_INSPECTOR, Args.inspector).activate.connect(() => {
                web_view.web_inspector.inspect_node(context_menu_element);
            });
        add_action(ACTION_OPEN_LINK, false).activate.connect(() => {
                context_menu_element.click();
            });
        add_action(ACTION_SELECT_ALL, true).activate.connect(() => {
                web_view.select_all();
            });
        add_action(ACTION_SAVE_IMAGE, false).activate.connect(on_save_image);

        insert_action_group("msg", message_actions);

        // Context menu

        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menus.ui"
        );
        context_menu_link = (MenuModel) builder.get_object("context_menu_link");
        context_menu_email = (MenuModel) builder.get_object("context_menu_email");
        context_menu_image = (MenuModel) builder.get_object("context_menu_image");
        context_menu_main = (MenuModel) builder.get_object("context_menu_main");
        if (Args.inspector) {
            context_menu_inspector =
                (MenuModel) builder.get_object("context_menu_inspector");
        }

        // Preview headers

        string? message_date = null;
        if (message.date != null) {
            Date.ClockFormat clock_format =
                GearyApplication.instance.config.clock_format;
            message_date = Date.pretty_print(message.date.value, clock_format);
        }

        preview_from.set_markup(format_sender_preview(message.from));
        preview_date.set_text(message_date ?? "");
        string preview_str = message.get_preview();
        preview_str = Geary.String.reduce_whitespace(preview_str);
        preview_body.set_text(preview_str);

        // Full headers

        set_flowbox_addresses(from, message.from, "bold");
        date.set_text(message_date ?? "");
        if (message.subject != null) {
            subject.set_text(message.subject.value);
            subject.set_visible(true);
        }
        set_header_addresses(to_header, message.to);
        set_header_addresses(cc_header, message.cc);
        set_header_addresses(bcc_header, message.bcc);

        // Web view

        web_view = new ConversationWebView();
        // Suppress default context menu.
        web_view.context_menu.connect(() => { return true; });
        web_view.size_allocate.connect((widget, allocation) => {
                web_view_allocation = allocation;
            });
        web_view.hovering_over_link.connect(on_hovering_over_link);
        web_view.selection_changed.connect(on_selection_changed);
        web_view.show();

        body_box.set_has_tooltip(true); // Used to show link URLs
        body_box.pack_start(web_view, true, true, 0);
    }

    /**
     * Shows the complete message and hides the preview headers.
     */
    public void show_message_body(bool include_transitions=true) {
        Gtk.RevealerTransitionType revealer = preview_revealer.get_transition_type();
        if (!include_transitions) {
            preview_revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        preview_revealer.set_reveal_child(false);
        preview_revealer.set_transition_type(revealer);

        revealer = header_revealer.get_transition_type();
        if (!include_transitions) {
            header_revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        header_revealer.set_reveal_child(true);
        header_revealer.set_transition_type(revealer);

        revealer = body_revealer.get_transition_type();
        if (!include_transitions) {
            body_revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        body_revealer.set_reveal_child(true);
        body_revealer.set_transition_type(revealer);
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
    public async void load_avatar(Soup.Session session, Cancellable load_cancellable) {
        // Queued messages are cancelled in ConversationViewer.clear()
        // rather than here using a callback on load_cancellable since
        // we don't have per-message control using
        // Soup.Session.queue_message.
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
            session.queue_message(message, (session, message) => {
                    if (message.status_code == 200) {
                        set_avatar(message.response_body.data);
                    }
                });
        }
    }

    /**
     * Starts loading the message body in the HTML view.
     */
    public async void load_message_body(Cancellable load_cancelled) {
        bool remote_images = false;
        bool load_images = false;
        string? body_text = null;
        try {
            if (message.has_html_body()) {
                body_text = message.get_html_body(inline_image_replacer);
            } else {
                body_text = message.get_plain_body(true, inline_image_replacer);
            }
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }

        body_text = clean_html_markup(body_text ?? "", message, out load_images);
        if (load_images) {
            Geary.Contact contact =
                contact_store.get_by_rfc822(message.get_primary_originator());
            bool contact_load = contact != null && contact.always_load_remote_images();
            if (contact_load || always_load_remote_images) {
                load_images = true;
            } else {
                remote_images_infobar.show();
            }
        }

        load_cancelled.cancelled.connect(() => { web_view.stop_loading(); });
        web_view.notify["load-status"].connect((source, param) => {
                if (web_view.load_status == WebKit.LoadStatus.FINISHED) {
                    if (load_images) {
                        show_images(false);
                    }
                    WebKit.DOM.HTMLElement html = (
                        web_view.get_dom_document().document_element as
                        WebKit.DOM.HTMLElement
                    );
                    if (html != null) {
                        try {
                            unset_controllable_quotes(html);
                        } catch (Error error) {
                            warning("Error unsetting controllable_quotes: %s",
                                    error.message);
                        }
                    }
                    Util.DOM.bind_event(web_view, "html", "contextmenu",
                               (Callback) on_context_menu, this);
                    Util.DOM.bind_event(web_view, "body a", "click",
                               (Callback) on_link_clicked, this);
                    Util.DOM.bind_event(web_view, ".quote_container > .shower", "click",
                               (Callback) on_show_quote_clicked, this);
                    Util.DOM.bind_event(web_view, ".quote_container > .hider", "click",
                               (Callback) on_hide_quote_clicked, this);

                    // XXX Not actually true since remote images will
                    // still be loading.
                    is_loading_complete = true;
                }
            });

        // Only load it after we've hooked up the signals above
        web_view.load_string(body_text, "text/html", "UTF8", "");
    }

    /**
     * Highlights user search terms in the message view.
     */
    public void highlight_search_terms(Gee.Set<string> search_matches) {
        // XXX Need to highlight subject, sender and recipient matches too

        // Remove existing highlights.
        web_view.unmark_text_matches();

        // Webkit's highlighting is ... weird.  In order to actually see
        // all the highlighting you're applying, it seems necessary to
        // start with the shortest string and work up.  If you don't, it
        // seems that shorter strings will overwrite longer ones, and
        // you're left with incomplete highlighting.
        Gee.ArrayList<string> ordered_matches = new Gee.ArrayList<string>();
        ordered_matches.add_all(search_matches);
        ordered_matches.sort((a, b) => a.length - b.length);

        foreach(string match in ordered_matches) {
            web_view.mark_text_matches(match, false, 0);
        }

        web_view.set_highlight_text_matches(true);
    }

    /**
     * Disables highlighting of any search terms in the message view.
     */
    public void unmark_search_terms() {
        web_view.set_highlight_text_matches(false);
        web_view.unmark_text_matches();
    }

    internal string? get_selection_for_quoting() {
        string? quote = null;
        WebKit.DOM.Document document = this.web_view.get_dom_document();
        WebKit.DOM.DOMSelection selection = document.default_view.get_selection();
        if (!selection.is_collapsed) {
            try {
                WebKit.DOM.Range range = selection.get_range_at(0);
                WebKit.DOM.HTMLElement dummy =
                    (WebKit.DOM.HTMLElement) document.create_element("div");
                bool include_dummy = false;
                WebKit.DOM.Node ancestor_node = range.get_common_ancestor_container();
                WebKit.DOM.Element? ancestor = ancestor_node as WebKit.DOM.Element;
                if (ancestor == null)
                    ancestor = ancestor_node.get_parent_element();
                // If the selection is part of a plain text message,
                // we have to stick it in an appropriately styled div,
                // so that new lines are preserved.
                if (Util.DOM.is_descendant_of(ancestor, ".plaintext")) {
                    dummy.get_class_list().add("plaintext");
                    dummy.set_attribute("style", "white-space: pre-wrap;");
                    include_dummy = true;
                }
                dummy.append_child(range.clone_contents());

                // Remove the chrome we put around quotes, leaving
                // only the blockquote element.
                WebKit.DOM.NodeList quotes =
                    dummy.query_selector_all(".quote_container");
                for (int i = 0; i < quotes.length; i++) {
                    WebKit.DOM.Element div = (WebKit.DOM.Element) quotes.item(i);
                    WebKit.DOM.Element blockquote = div.query_selector("blockquote");
                    div.get_parent_element().replace_child(blockquote, div);
                }

                quote = include_dummy ? dummy.get_outer_html() : dummy.get_inner_html();
            } catch (Error error) {
                debug("Problem getting selected text: %s", error.message);
            }
        }
        return quote;
    }

    private SimpleAction add_action(string name, bool enabled) {
        SimpleAction action = new SimpleAction(name, null);
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

    private void set_header_addresses(Gtk.Box header,
                                      Geary.RFC822.MailboxAddresses? addresses) {
        if (addresses != null && addresses.size > 0) {
            Gtk.FlowBox box = header.get_children().nth(1).data as Gtk.FlowBox;
            if (box != null) {
                set_flowbox_addresses(box, addresses);
            }
            header.set_visible(true);
        }
    }

    private void set_flowbox_addresses(Gtk.FlowBox address_box,
                                       Geary.RFC822.MailboxAddresses? addresses,
                                       string weight = "normal") {
        string dim_color = GtkUtil.pango_color_from_theme(
            address_box.get_style_context(), "insensitive_fg_color"
        );
        foreach (Geary.RFC822.MailboxAddress addr in addresses) {
            Gtk.Label label = new Gtk.Label(null);
            //label.set_halign(Gtk.Align.START);
            //label.set_valign(Gtk.Align.BASELINE);
            //label.set_ellipsize(Pango.EllipsizeMode.END);
            //label.set_xalign(0.0f);

            string name = Geary.HTML.escape_markup(addr.name);
            string address = Geary.HTML.escape_markup(addr.address);
            if (!Geary.String.is_empty(addr.name) && name != address) {
                label.set_markup(
                    "<span weight=\"%s\">%s</span> <span color=\"%s\">%s</span>"
                    .printf(weight, name, dim_color, address)
                    );
            } else {
                label.set_markup(
                    "<span weight=\"%s\">%s</span>".printf(weight, address)
                    );
            }

            Gtk.FlowBoxChild child = new Gtk.FlowBoxChild();
            child.add(label);
            child.set_halign(Gtk.Align.START);
            //child.set_valign(Gtk.Align.START);
            child.show_all();

            address_box.add(child);
        }
    }

    private string format_sender_preview(Geary.RFC822.MailboxAddresses? addresses) {
        string dim_color = GtkUtil.pango_color_from_theme(
            get_style_context(), "insensitive_fg_color"
        );
        int i = 0;
        string value = "";
        Gee.List<Geary.RFC822.MailboxAddress> list = addresses.get_all();
        foreach (Geary.RFC822.MailboxAddress addr in list) {
            string address = Geary.HTML.escape_markup(addr.address);
            if (!Geary.String.is_empty(addr.name)) {
                string name = Geary.HTML.escape_markup(addr.name);
                value += "<span weight=\"bold\">%s</span> <span color=\"%s\">%s</span>".printf(
                    name, dim_color, address
                );
            } else {
                value += "<span weight=\"bold\">%s</span>".printf(address);
            }

            if (++i < list.size)
                value += ", ";
        }
        return value;
    }

    private void set_avatar(uint8[] image_data) {
        Gdk.Pixbuf avatar_buf = null;
        Gdk.PixbufLoader loader = new Gdk.PixbufLoader();
        try {
            loader.write(image_data);
            loader.close();
            avatar_buf = loader.get_pixbuf();
        } catch (Error err) {
            debug("Error loading Gravatar response: %s", err.message);
        }

        if (avatar_buf != null) {
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
        
        if (!is_content_type_supported_inline(content_type)) {
            debug("Not displaying %s inline: unsupported Content-Type", content_type.to_string());
            
            return null;
        }
        
        // Even if the image doesn't need to be rotated, there's a win here: by reducing the size
        // of the image at load time, it reduces the amount of work that has to be done to insert
        // it into the HTML and then decoded and displayed for the user ... note that we currently
        // have the doucment set up to reduce the size of the image to fit in the viewport, and a
        // scaled load-and-deode is always faster than load followed by scale.
        Geary.Memory.Buffer rotated_image = buffer;
        string mime_type = content_type.get_mime_type();
        try {
            Gdk.PixbufLoader loader = new Gdk.PixbufLoader();
            loader.size_prepared.connect(on_inline_image_size_prepared);
            
            Geary.Memory.UnownedBytesBuffer? unowned_buffer = buffer as Geary.Memory.UnownedBytesBuffer;
            if (unowned_buffer != null)
                loader.write(unowned_buffer.to_unowned_uint8_array());
            else
                loader.write(buffer.get_uint8_array());
            loader.close();
            
            Gdk.Pixbuf? pixbuf = loader.get_pixbuf();
            if (pixbuf != null) {
                pixbuf = pixbuf.apply_embedded_orientation();
                
                // trade-off here between how long it takes to compress the data and how long it
                // takes to turn it into Base-64 (coupled with how long it takes WebKit to then
                // Base-64 decode and uncompress it)
                uint8[] image_data;
                pixbuf.save_to_buffer(out image_data, "png", "compression", "5");
                
                // Save length before transferring ownership (which frees the array)
                int image_length = image_data.length;
                rotated_image = new Geary.Memory.ByteBuffer.take((owned) image_data, image_length);
                mime_type = "image/png";
            }
        } catch (Error err) {
            debug("Unable to load and rotate image %s for display: %s", filename, err.message);
        }
        
        // store so later processing of the message doesn't replace this element with the original
        // MIME part
        string? escaped_content_id = null;
        if (!Geary.String.is_empty(content_id)) {
            replaced_content_ids.add(content_id);
            escaped_content_id = Geary.HTML.escape_markup(content_id);
        }
        
        // Store the original buffer and its filename in a local map so they can be recalled later
        // (if the user wants to save it) ... note that Content-ID is optional and there's no
        // guarantee that filename will be unique, even in the same message, so need to generate
        // a unique identifier for each object
        ReplacedImage replaced_image = new ReplacedImage(next_replaced_buffer_number++, filename,
            buffer);
        replaced_images.set(replaced_image.id, replaced_image);
        
        return "<img alt=\"%s\" class=\"%s %s\" src=\"%s\" replaced-id=\"%s\" %s />".printf(
            Geary.HTML.escape_markup(filename),
            DATA_IMAGE_CLASS, REPLACED_IMAGE_CLASS,
            Util.DOM.assemble_data_uri(mime_type, rotated_image),
            Geary.HTML.escape_markup(replaced_image.id),
            escaped_content_id != null ? @"cid=\"$escaped_content_id\"" : "");
    }
    
    // Called by Gdk.PixbufLoader when the image's size has been determined but not loaded yet ...
    // this allows us to load the image scaled down, for better performance when manipulating and
    // writing the data URI for WebKit
    private static void on_inline_image_size_prepared(Gdk.PixbufLoader loader, int width, int height) {
        // easier to use as local variable than have the const listed everywhere in the code
        // IN ALL SCREAMING CAPS
        int scale = MAX_INLINE_IMAGE_MAJOR_DIM;
        
        // Borrowed liberally from Shotwell's Dimensions.get_scaled() method
        
        // check for existing fit
        if (width <= scale && height <= scale)
            return;
        
        int adj_width, adj_height;
        if ((width - scale) > (height - scale)) {
            double aspect = (double) scale / (double) width;
            
            adj_width = scale;
            adj_height = (int) Math.round((double) height * aspect);
        } else {
            double aspect = (double) scale / (double) height;
            
            adj_width = (int) Math.round((double) width * aspect);
            adj_height = scale;
        }
        
        loader.set_size(adj_width, adj_height);
    }

    private string clean_html_markup(string text, Geary.RFC822.Message message, out bool remote_images) {
        remote_images = false;
        try {
            string inner_text = text;
            
            // If email HTML has a BODY, use only that
            GLib.Regex body_regex = new GLib.Regex("<body([^>]*)>(.*)</body>",
                GLib.RegexCompileFlags.DOTALL);
            GLib.MatchInfo matches;
            if (body_regex.match(text, 0, out matches)) {
                inner_text = matches.fetch(2);
                string attrs = matches.fetch(1);
                if (attrs != "")
                    inner_text = @"<div$attrs>$inner_text</div>";
            }
            
            // Create a workspace for manipulating the HTML.
            WebKit.DOM.HTMLElement container = web_view.create_div();
            container.set_inner_html(inner_text);
            
            // Get all the top level block quotes and stick them into a hide/show controller.
            WebKit.DOM.NodeList blockquote_list = container.query_selector_all("blockquote");
            for (int i = 0; i < blockquote_list.length; ++i) {
                // Get the nodes we need.
                WebKit.DOM.Node blockquote_node = blockquote_list.item(i);
                WebKit.DOM.Node? next_sibling = blockquote_node.get_next_sibling();
                WebKit.DOM.Node parent = blockquote_node.get_parent_node();

                // Make sure this is a top level blockquote.
                if (Util.DOM.node_is_child_of(blockquote_node, "BLOCKQUOTE")) {
                    continue;
                }

                // parent
                //     quote_container
                //         blockquote
                //     sibling
                WebKit.DOM.Element quote_container = create_quote_container();
                Util.DOM.select(quote_container, ".quote").append_child(blockquote_node);
                if (next_sibling == null) {
                    parent.append_child(quote_container);
                } else {
                    parent.insert_before(quote_container, next_sibling);
                }
            }

            // Now look for the signature.
            wrap_html_signature(ref container);

            // Then look for all <img> tags. Inline images are replaced with
            // data URLs.
            WebKit.DOM.NodeList inline_list = container.query_selector_all("img");
            Gee.HashSet<string> inlined_content_ids = new Gee.HashSet<string>();
            for (ulong i = 0; i < inline_list.length; ++i) {
                // Get the MIME content for the image.
                WebKit.DOM.HTMLImageElement img = (WebKit.DOM.HTMLImageElement) inline_list.item(i);
                string? src = img.get_attribute("src");
                if (Geary.String.is_empty(src))
                    continue;
                
                // if no Content-ID, then leave as-is, but note if a non-data: URI is being used for
                // purposes of detecting remote images
                string? content_id = src.has_prefix("cid:") ? src.substring(4) : null;
                if (Geary.String.is_empty(content_id)) {
                    remote_images = remote_images || !src.has_prefix("data:");
                    
                    continue;
                }
                
                // if image has a Content-ID and it's already been replaced by the image replacer,
                // drop this tag, otherwise fix up this one with the Base-64 data URI of the image
                if (!replaced_content_ids.contains(content_id)) {
                    string? filename = message.get_content_filename_by_mime_id(content_id);
                    Geary.Memory.Buffer image_content = message.get_content_by_mime_id(content_id);
                    Geary.Memory.UnownedBytesBuffer? unowned_buffer =
                        image_content as Geary.Memory.UnownedBytesBuffer;
                    
                    // Get the content type.
                    string guess;
                    if (unowned_buffer != null)
                        guess = ContentType.guess(null, unowned_buffer.to_unowned_uint8_array(), null);
                    else
                        guess = ContentType.guess(null, image_content.get_uint8_array(), null);
                    
                    string mimetype = ContentType.get_mime_type(guess);
                    
                    // Replace the SRC to a data URI, the class to a known label for the popup menu,
                    // and the ALT to its filename, if supplied
                    img.remove_attribute("src");  // Work around a WebKitGTK+ crash. Bug 764152
                    img.set_attribute("src", Util.DOM.assemble_data_uri(mimetype, image_content));
                    img.set_attribute("class", DATA_IMAGE_CLASS);
                    if (!Geary.String.is_empty(filename))
                        img.set_attribute("alt", filename);
                    
                    // stash here so inlined image isn't listed as attachment (esp. if it has no
                    // Content-Disposition)
                    inlined_content_ids.add(content_id);
                    attachment_displayed_inline(content_id);
                } else {
                    // replaced by data: URI, remove this tag and let the inserted one shine through
                    img.parent_element.remove_child(img);
                }
            }
            
            // Remove any inline images that were referenced through Content-ID
            foreach (string cid in inlined_content_ids) {
                try {
                    string escaped_cid = Geary.HTML.escape_markup(cid);
                    WebKit.DOM.Element? img = container.query_selector(@"[cid='$escaped_cid']");
                    if (img != null)
                        img.parent_element.remove_child(img);
                } catch (Error error) {
                    debug("Error removing inlined image: %s", error.message);
                }
            }
            
            // Now return the whole message.
            return container.get_inner_html();
        } catch (Error e) {
            debug("Error modifying HTML message: %s", e.message);
            return text;
        }
    }
    
    private WebKit.DOM.HTMLDivElement create_quote_container() throws Error {
        WebKit.DOM.HTMLDivElement quote_container = web_view.create_div();
        quote_container.set_attribute(
            "class", "quote_container controllable hide"
        );
        quote_container.set_inner_html("""
<div class="shower"><input type="button" value="▼        ▼        ▼" /></div>
<div class="hider"><input type="button" value="▲        ▲        ▲" /></div>
<div class="quote"></div>""");
        return quote_container;
    }

    private void wrap_html_signature(ref WebKit.DOM.HTMLElement container) throws Error {
        // Most HTML signatures fall into one of these designs which are handled by this method:
        //
        // 1. GMail:            <div>-- </div>$SIGNATURE
        // 2. GMail Alternate:  <div><span>-- </span></div>$SIGNATURE
        // 3. Thunderbird:      <div>-- <br>$SIGNATURE</div>
        //
        WebKit.DOM.NodeList div_list = container.query_selector_all("div,span,p");
        int i = 0;
        Regex sig_regex = new Regex("^--\\s*$");
        Regex alternate_sig_regex = new Regex("^--\\s*(?:<br|\\R)");
        for (; i < div_list.length; ++i) {
            // Get the div and check that it starts a signature block and is not inside a quote.
            WebKit.DOM.HTMLElement div = div_list.item(i) as WebKit.DOM.HTMLElement;
            string inner_html = div.get_inner_html();
            if ((sig_regex.match(inner_html) || alternate_sig_regex.match(inner_html)) &&
                !Util.DOM.node_is_child_of(div, "BLOCKQUOTE")) {
                break;
            }
        }

        // If we have a signature, move it and all of its following siblings that are not quotes
        // inside a signature div.
        if (i == div_list.length) {
            return;
        }
        WebKit.DOM.Node elem = div_list.item(i) as WebKit.DOM.Node;
        WebKit.DOM.Element parent = elem.get_parent_element();
        WebKit.DOM.HTMLElement signature_container = web_view.create_div();
        signature_container.set_attribute("class", "signature");
        do {
            // Get its sibling _before_ we move it into the signature div.
            WebKit.DOM.Node? sibling = elem.get_next_sibling();
            signature_container.append_child(elem);
            elem = sibling;
        } while (elem != null);
        parent.append_child(signature_container);
    }
    
    private void unset_controllable_quotes(WebKit.DOM.HTMLElement element) throws GLib.Error {
        WebKit.DOM.NodeList quote_list = element.query_selector_all(".quote_container.controllable");
        for (int i = 0; i < quote_list.length; ++i) {
            WebKit.DOM.Element quote_container = quote_list.item(i) as WebKit.DOM.Element;
            long scroll_height = quote_container.query_selector(".quote").scroll_height;
            // If the message is hidden, scroll_height will be 0.
            if (scroll_height > 0 && scroll_height < QUOTE_SIZE_THRESHOLD) {
                quote_container.class_list.remove("controllable");
                quote_container.class_list.remove("hide");
            }
        }
    }
    
    private void show_images(bool remember) {
        try {
            WebKit.DOM.Element body = Util.DOM.select(
                web_view.get_dom_document(), "body"
            );
            if (body == null) {
                warning("Could not find message body");
            } else {
                WebKit.DOM.NodeList nodes = body.get_elements_by_tag_name("img");
                for (ulong i = 0; i < nodes.length; i++) {
                    WebKit.DOM.Element? element = nodes.item(i) as WebKit.DOM.Element;
                    if (element == null || !element.has_attribute("src"))
                        continue;
                    
                    string src = element.get_attribute("src");
                    if (!web_view.is_always_loaded(src)) {
                        // Workaround a WebKitGTK+ 2.4.10 crash. See Bug 763933
                        element.remove_attribute("src");
                        element.set_attribute("src", web_view.allow_prefix + src);
                    }
                }
            }
        } catch (Error error) {
            warning("Error showing images: %s", error.message);
        }

        if (remember) {
            flag_remote_images();
        }
    }

    private static bool is_content_type_supported_inline(Geary.Mime.ContentType content_type) {
        foreach (string mime_type in INLINE_MIME_TYPES) {
            try {
                if (content_type.is_mime_type(mime_type))
                    return true;
            } catch (Error err) {
                debug("Unable to compare MIME type %s: %s", mime_type, err.message);
            }
        }

        return false;
    }

    /*
     * Test whether text looks like a URI that leads somewhere other than href.  The text
     * will have a scheme prepended if it doesn't already have one, and the short versions
     * have the scheme skipped and long paths truncated.
     */
    private bool deceptive_text(string href, ref string text, out string href_short,
        out string text_short) {
        href_short = "";
        text_short = "";
        // mailto URLs have a different form, and the worst they can do is pop up a composer,
        // so we don't trigger on them.
        if (href.has_prefix("mailto:"))
            return false;
        
        // First, does text look like a URI?  Right now, just test whether it has
        // <string>.<string> in it.  More sophisticated tests are possible.
        GLib.MatchInfo text_match, href_match;
        try {
            GLib.Regex domain = new GLib.Regex(
                "([a-z]*://)?"                  // Optional scheme
                + "([^\\s:/]+\\.[^\\s:/\\.]+)"  // Domain
                + "(/[^\\s]*)?"                 // Optional path
                );
            if (!domain.match(text, 0, out text_match))
                return false;
            if (!domain.match(href, 0, out href_match)) {
                // If href doesn't look like a URL, something is fishy, so warn the user
                href_short = href + _(" (Invalid?)");
                text_short = text;
                return true;
            }
        } catch (Error error) {
            warning("Error in Regex text for deceptive urls: %s", error.message);
            return false;
        }
        
        // Second, do the top levels of the two domains match?  We compare the top n levels,
        // where n is the minimum of the number of levels of the two domains.
        string[] href_parts = href_match.fetch_all();
        string[] text_parts = text_match.fetch_all();
        string[] text_domain = text_parts[2].down().reverse().split(".");
        string[] href_domain = href_parts[2].down().reverse().split(".");
        for (int i = 0; i < text_domain.length && i < href_domain.length; i++) {
            if (text_domain[i] != href_domain[i]) {
                if (href_parts[1] == "")
                    href_parts[1] = "http://";
                if (text_parts[1] == "")
                    text_parts[1] = href_parts[1];
                string temp;
                assemble_uris(href_parts, out temp, out href_short);
                assemble_uris(text_parts, out text, out text_short);
                return true;
            }
        }
        return false;
    }
    
    private void assemble_uris(string[] parts, out string full, out string short_) {
        full = parts[1] + parts[2];
        short_ = parts[2];
        if (parts.length == 4 && parts[3] != "/") {
            full += parts[3];
            if (parts[3].length > 20)
                short_ += parts[3].substring(0, 20) + "…";
            else
                short_ += parts[3];
        }
    }

    private ReplacedImage? get_replaced_image() {
        ReplacedImage? image = null;
        string? replaced_id = context_menu_element.get_attribute("replaced-id");
        if (!Geary.String.is_empty(replaced_id)) {
            image = replaced_images.get(replaced_id);
        }
        return image;
    }

    private static void on_show_quote_clicked(WebKit.DOM.Element element,
                                              WebKit.DOM.Event event) {
        try {
            ((WebKit.DOM.HTMLElement) element.parent_node).class_list.remove("hide");
        } catch (Error error) {
            warning("Error showing quote: %s", error.message);
        }
    }

    private static void on_hide_quote_clicked(WebKit.DOM.Element element,
                                              WebKit.DOM.Event event,
                                              ConversationMessage message) {
        try {
            ((WebKit.DOM.HTMLElement) element.parent_node).class_list.add("hide");
            message.web_view.queue_resize();
        } catch (Error error) {
            warning("Error toggling quote: %s", error.message);
        }
    }

    private static void on_context_menu(WebKit.DOM.Element element,
                                        WebKit.DOM.Event event,
                                        ConversationMessage message) {
        message.on_context_menu_self(element, event);
        event.prevent_default();
    }

    private void on_context_menu_self(WebKit.DOM.Element element,
                                      WebKit.DOM.Event event) {
        context_menu_element = event.get_target() as WebKit.DOM.HTMLElement;

        if (context_menu != null) {
            context_menu.detach();
        }

        // Build a new context menu every time the user clicks because
        // at the moment under GTK+3.20 it's far easier to selectively
        // build a new menu model from pieces as we do here, then to
        // have a single menu model and disable the parts we don't
        // need.
        Menu model = new Menu();
        if (hover_url != null) {
            if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
                model.append_section(null, context_menu_email);
            } else {
                model.append_section(null, context_menu_link);
            }
        }
        if (context_menu_element.local_name.down() == "img") {
            ReplacedImage image = get_replaced_image();
            set_action_enabled(ACTION_SAVE_IMAGE, image != null);
            model.append_section(null, context_menu_image);
        }
        model.append_section(null, context_menu_main);
        if (context_menu_inspector != null) {
            model.append_section(null, context_menu_inspector);
        }

        context_menu = new Gtk.Menu.from_model(model);
        context_menu.attach_to_widget(this, null);
        context_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    }

    private static void on_link_clicked(WebKit.DOM.Element element,
                                        WebKit.DOM.Event event,
                                        ConversationMessage message) {
        if (message.on_link_clicked_self(element)) {
            event.prevent_default();
        }
    }

    // Check for possible phishing links, displays a popover if found.
    // If not, lets it go through to the default handler.
    private bool on_link_clicked_self(WebKit.DOM.Element element) {
        string? href = element.get_attribute("href");
        if (Geary.String.is_empty(href))
            return false;
        string text = ((WebKit.DOM.HTMLElement) element).get_inner_text();
        string href_short, text_short;
        if (!deceptive_text(href, ref text, out href_short, out text_short))
            return false;

        // Escape text and especially URLs since we got them from the
        // HREF, and Gtk.Label.set_markup is a strict parser.
        good_link_label.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", text, text_short)
        );
        bad_link_label.set_markup(
            Markup.printf_escaped("<a href=\"%s\">%s</a>", href, href_short)
        );

        // Work out the link's position, update the popover.
        Gdk.Rectangle link_rect = Gdk.Rectangle();
        web_view.get_allocation(out link_rect);
        link_rect.x += (int) element.get_offset_left();
        link_rect.y += (int) element.get_offset_top();
        WebKit.DOM.Element? offset_parent = element.get_offset_parent();
        while (offset_parent != null) {
            link_rect.x += (int) offset_parent.get_offset_left();
            link_rect.y += (int) offset_parent.get_offset_top();
            offset_parent = offset_parent.get_offset_parent();
        }
        link_rect.width = (int) element.get_offset_width();
        link_rect.height = (int) element.get_offset_height();
        link_popover.set_pointing_to(link_rect);

        link_popover.show();
        return true;
    }

    private void on_hovering_over_link(string? title, string? url) {
        if (url != null) {
            hover_url = Uri.unescape_string(url);
            bool is_email = hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME);
            set_action_enabled(ACTION_OPEN_LINK, true);
            set_action_enabled(ACTION_COPY_LINK, !is_email);
            set_action_enabled(ACTION_COPY_EMAIL, is_email);
        } else {
            hover_url = null;
            set_action_enabled(ACTION_OPEN_LINK, false);
            set_action_enabled(ACTION_COPY_LINK, false);
            set_action_enabled(ACTION_COPY_EMAIL, false);
        }

        // Use tooltip on the containing box since the web_view
        // doesn't want to pay ball.
        body_box.set_tooltip_text(hover_url);
        body_box.trigger_tooltip_query();
    }

    private void on_selection_changed() {
        bool has_selection = false;
        if (web_view.has_selection()) {
            WebKit.DOM.Document document = web_view.get_dom_document();
            has_selection = !document.default_view.get_selection().is_collapsed;
        }
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

    private void on_copy_link() {
        // Put the current link in clipboard.
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        clipboard.set_text(hover_url, -1);
        clipboard.store();
    }

    private void on_copy_email_address() {
        // Put the current email address in clipboard.
        Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
            clipboard.set_text(hover_url.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1), -1);
        }
        clipboard.store();
    }

    private void on_save_image() {
        ReplacedImage? replaced_image = get_replaced_image();
        save_image(replaced_image.filename, replaced_image.buffer);
    }

}
