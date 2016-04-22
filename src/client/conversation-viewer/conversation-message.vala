/*
 * Copyright 2011-2015 Yorba Foundation
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying an {@link Geary.RFC822.Message}.
 *
 * This widget corresponds to {@link Geary.RFC822.Message}, displaying
 * both the message's headers and body. Any attachments and sub
 * messages are handled by {@link ConversationEmail}, which typically
 * embeds at least one instance of this class.
 */
[GtkTemplate (ui = "/org/gnome/Geary/conversation-message.ui")]
public class ConversationMessage : Gtk.Box {
    

    // Internal class to associate inline image buffers (replaced by rotated scaled versions of
    // them) so they can be saved intact if the user requires it
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


    // The message being displayed
    public Geary.RFC822.Message message { get; private set; }

    // The HTML viewer to view the emails.
    public ConversationWebView web_view { get; private set; }

    // The allocation for the web view
    public Gdk.Rectangle web_view_allocation { get; private set; }

    // Has the message body been been fully loaded?
    public bool is_loading_complete = false;

    [GtkChild]
    public Gtk.Box summary_box; // not yet supported: { get; private set; }

    [GtkChild]
    public Gtk.Box infobar_box; // not yet supported: { get; private set; }

    [GtkChild]
    private Gtk.Revealer preview_revealer;
    [GtkChild]
    private Gtk.Image preview_avatar;
    [GtkChild]
    private Gtk.Label from_preview;
    [GtkChild]
    private Gtk.Label body_preview;

    [GtkChild]
    private Gtk.Revealer header_revealer;
    [GtkChild]
    private Gtk.Image header_avatar;
    [GtkChild]
    private Gtk.Box from_header;
    [GtkChild]
    private Gtk.Box to_header;
    [GtkChild]
    private Gtk.Box cc_header;
    [GtkChild]
    private Gtk.Box bcc_header;
    [GtkChild]
    private Gtk.Box subject_header;
    [GtkChild]
    private Gtk.Box date_header;

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

    // The contacts for the message's account
    private Geary.ContactStore contact_store;

    // Should any remote messages be always loaded and displayed?
    private bool always_load_remote_images;

    // Contains the current mouse-over'ed link URL, if any
    private string? hover_url = null;

    private int next_replaced_buffer_number = 0;
    private Gee.HashMap<string, ReplacedImage> replaced_images = new Gee.HashMap<string, ReplacedImage>();
    private Gee.HashSet<string> replaced_content_ids = new Gee.HashSet<string>();

    // Fired when an attachment is displayed inline
    public signal void attachment_displayed_inline(string id);

    // Fired when remote image load requested for sender
    public signal void flag_remote_images();

    // Fired when remote image load requested for sender
    public signal void remember_remote_images();


    public ConversationMessage(Geary.RFC822.Message message,
                               Geary.ContactStore contact_store,
                               bool always_load_remote_images) {
        this.message = message;
        this.contact_store = contact_store;
        this.always_load_remote_images = always_load_remote_images;

        // Preview headers

        from_preview.set_text(format_addresses(message.from));

        string preview_str = message.get_preview();
        preview_str = Geary.String.reduce_whitespace(preview_str);
        body_preview.set_text(preview_str);

        // Full headers

        set_header_text(from_header, format_addresses(message.from));
        if (message.to != null) {
            set_header_text(to_header, format_addresses(message.to));
        }
        if (message.cc != null) {
            set_header_text(cc_header, format_addresses(message.cc));
        }
        if (message.bcc != null) {
            set_header_text(bcc_header, format_addresses(message.bcc));
        }
        if (message.subject != null) {
            set_header_text(subject_header, message.subject.value);
        }
        if (message.date != null) {
            Date.ClockFormat clock_format =
                GearyApplication.instance.config.clock_format;
            set_header_text(
                date_header,
                Date.pretty_print_verbose(message.date.value, clock_format)
            );
        }

        web_view = new ConversationWebView();
        web_view.show();
        // web_view.context_menu.connect(() => { return true; }); // Suppress default context menu.
        // web_view.realize.connect( () => { web_view.get_vadjustment().value_changed.connect(mark_read); });
        // web_view.size_allocate.connect(mark_read);
        web_view.size_allocate.connect((widget, allocation) => {
                web_view_allocation = allocation;
            });
        web_view.hovering_over_link.connect(on_hovering_over_link);

        body_box.set_has_tooltip(true); // Used to show link URLs
        body_box.pack_start(web_view, true, true, 0);
    }

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

    public void hide_message_body() {
        preview_revealer.set_reveal_child(true);
        header_revealer.set_reveal_child(false);
        body_revealer.set_reveal_child(false);
    }

    public async void load_avatar(Soup.Session session, Cancellable load_cancellable) {
        // Queued messages are cancelled in ConversationViewer.clear()
        // rather than here using a callback on load_cancellable since
        // we don't have per-message control using
        // Soup.Session.queue_message.
        Geary.RFC822.MailboxAddress? primary = message.get_primary_originator();
        if (primary != null) {
            int window_scale = get_window().get_scale_factor();
            int pixel_size = header_avatar.get_pixel_size();
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
                    bind_event(web_view, "body a", "click",
                               (Callback) on_link_clicked, this);
                    bind_event(web_view, ".quote_container > .shower", "click",
                               (Callback) on_show_quote_clicked, this);
                    bind_event(web_view, ".quote_container > .hider", "click",
                               (Callback) on_hide_quote_clicked, this);

                    // XXX Not actually true since remote images will
                    // still be loading.
                    is_loading_complete = true;
                }
            });

        // Only load it after we've hooked up the signals above
        web_view.load_string(body_text, "text/html", "UTF8", "");
    }

    // Appends email address fields to the header.
    private string format_addresses(Geary.RFC822.MailboxAddresses? addresses) {
        int i = 0;
        string value = "";
        Gee.List<Geary.RFC822.MailboxAddress> list = addresses.get_all();
        foreach (Geary.RFC822.MailboxAddress a in list) {
            value += a.to_string();

            if (++i < list.size)
                value += ", ";
        }

        return value;
    }

    private static void set_header_text(Gtk.Box header, string text) {
        ((Gtk.Label) header.get_children().nth(1).data).set_text(text);
        header.set_visible(true);
    }

    private void set_avatar(uint8[] image_data) {
        Gdk.Pixbuf avatar = null;
        Gdk.PixbufLoader loader = new Gdk.PixbufLoader();
        try {
            loader.write(image_data);
            loader.close();
            avatar = loader.get_pixbuf();
        } catch (Error err) {
            debug("Error loading Gravatar response: %s", err.message);
        }

        if (avatar != null) {
            Gdk.Window window = get_window();
            int window_scale = window.get_scale_factor();
            int preview_size = preview_avatar.pixel_size * window_scale;
            preview_avatar.set_from_surface(
                Gdk.cairo_surface_create_from_pixbuf(
                    avatar.scale_simple(
                        preview_size, preview_size, Gdk.InterpType.BILINEAR
                    ),
                    window_scale,
                    window)
            );
            int header_size = header_avatar.pixel_size * window_scale;
            if (avatar.width != header_size) {
                avatar = avatar.scale_simple(
                    header_size, header_size, Gdk.InterpType.BILINEAR
                );
            }
            header_avatar.set_from_surface(
                Gdk.cairo_surface_create_from_pixbuf(avatar, window_scale, window)
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
            assemble_data_uri(mime_type, rotated_image),
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
    
    // private Gtk.Menu build_context_menu(Geary.Email email, WebKit.DOM.Element clicked_element) {
    //     Gtk.Menu menu = new Gtk.Menu();
        
    //     if (web_view.can_copy_clipboard()) {
    //         // Add a menu item for copying the current selection.
    //         Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("_Copy"));
    //         item.activate.connect(on_copy_text);
    //         menu.append(item);
    //     }
        
    //     if (hover_url != null) {
    //         if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME)) {
    //             // Add a menu item for copying the address.
    //             Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("Copy _Email Address"));
    //             item.activate.connect(on_copy_email_address);
    //             menu.append(item);
    //         } else {
    //             // Add a menu item for copying the link.
    //             Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("Copy _Link"));
    //             item.activate.connect(on_copy_link);
    //             menu.append(item);
    //         }
    //     }
        
    //     // Select message.
    //     if (!is_hidden()) {
    //         Gtk.MenuItem select_message_item = new Gtk.MenuItem.with_mnemonic(_("Select _Message"));
    //         select_message_item.activate.connect(() => {on_select_message(clicked_element);});
    //         menu.append(select_message_item);
    //     }
        
    //     // Select all.
    //     Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(_("Select _All"));
    //     select_all_item.activate.connect(on_select_all);
    //     menu.append(select_all_item);
        
    //     // Inspect.
    //     if (Args.inspector) {
    //         Gtk.MenuItem inspect_item = new Gtk.MenuItem.with_mnemonic(_("_Inspect"));
    //         inspect_item.activate.connect(() => {web_view.web_inspector.inspect_node(clicked_element);});
    //         menu.append(inspect_item);
    //     }

    //     return menu;
    // }

    // private void on_data_image_menu(WebKit.DOM.Element element, WebKit.DOM.Event event) {
    //     event.stop_propagation();
        
    //     string? replaced_id = element.get_attribute("replaced-id");
    //     if (Geary.String.is_empty(replaced_id))
    //         return;
        
    //     ReplacedImage? replaced_image = replaced_images.get(replaced_id);
    //     if (replaced_image == null)
    //         return;
        
    //     image_menu = new Gtk.Menu();
    //     image_menu.selection_done.connect(() => {
    //         image_menu = null;
    //      });
        
    //     Gtk.MenuItem save_image_item = new Gtk.MenuItem.with_mnemonic(_("_Save Image As..."));
    //     save_image_item.activate.connect(() => {
    //         save_buffer_to_file(replaced_image.filename, replaced_image.buffer);
    //     });
    //     image_menu.append(save_image_item);

    //     image_menu.show_all();

    //     image_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    // }

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
                if (node_is_child_of(blockquote_node, "BLOCKQUOTE")) {
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
                    img.set_attribute("src", assemble_data_uri(mimetype, image_content));
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
                !node_is_child_of(div, "BLOCKQUOTE")) {
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
        // Use tooltip on the containing box since the web_view
        // doesn't want to pay ball.
        hover_url = (url != null) ? Uri.unescape_string(url) : null;
        body_box.set_tooltip_text(hover_url);
        body_box.trigger_tooltip_query();
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

    // private void on_copy_text() {
    //     web_view.copy_clipboard();
    // }
    
    // private void on_copy_link() {
    //     // Put the current link in clipboard.
    //     Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
    //     clipboard.set_text(hover_url, -1);
    //     clipboard.store();
    // }

    // private void on_copy_email_address() {
    //     // Put the current email address in clipboard.
    //     Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
    //     if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME))
    //         clipboard.set_text(hover_url.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1), -1);
    //     else
    //         clipboard.set_text(hover_url, -1);
    //     clipboard.store();
    // }
    
    // private void on_select_all() {
    //     web_view.select_all();
    // }
    
    // private void on_select_message(WebKit.DOM.Element email_element) {
    //     try {
    //         web_view.get_dom_document().get_default_view().get_selection().select_all_children(email_element);
    //     } catch (Error error) {
    //         warning("Could not make selection: %s", error.message);
    //     }
    // }

}
