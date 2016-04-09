/*
 * Copyright 2011-2015 Yorba Foundation
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for displaying a message in a conversation.
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
    private const int ATTACHMENT_PREVIEW_SIZE = 50;
    private const string REPLACED_IMAGE_CLASS = "replaced_inline_image";
    private const string DATA_IMAGE_CLASS = "data_inline_image";
    private const int MAX_INLINE_IMAGE_MAJOR_DIM = 1024;
    private const int QUOTE_SIZE_THRESHOLD = 120;
    
    [GtkChild]
    private Gtk.Image avatar_image;

    [GtkChild]
    private Gtk.Revealer from_revealer;

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
    private Gtk.Label preview_label;

    [GtkChild]
    private Gtk.Button flag_button;

    [GtkChild]
    private Gtk.MenuButton message_menubutton;

    [GtkChild]
    private Gtk.Revealer body_revealer;

    [GtkChild]
    private Gtk.Box body_box;

    // The email message being displayed
    public Geary.Email email { get; private set; }

    // The message being displayed
    public Geary.RFC822.Message message { get; private set; }

    // The folder containing the message
    private Geary.Folder containing_folder = null; // XXX weak??

    // The HTML viewer to view the emails.
    private ConversationWebView web_view { get; private set; }

    // Overlay consisting of a label in front of a webpage
    private Gtk.Overlay message_overlay;
    
    // Label for displaying overlay messages.
    //private Gtk.Label message_overlay_label;
    
    //private string? hover_url = null;
    private Gee.HashSet<string> inlined_content_ids = new Gee.HashSet<string>();
    private int next_replaced_buffer_number = 0;
    private Gee.HashMap<string, ReplacedImage> replaced_images = new Gee.HashMap<string, ReplacedImage>();
    private Gee.HashSet<string> replaced_content_ids = new Gee.HashSet<string>();

    public ConversationMessage(Geary.Email email, Geary.Folder containing_folder) {
        this.email = email;
        this.containing_folder = containing_folder;

        try {
            message = email.get_message();
        } catch (Error error) {
            debug("Error loading  message: %s", error.message);
            return;
        }

        set_header_text(from_header, format_addresses(message.from));

        if (message.to != null) {
            set_header_text(to_header, format_addresses(message.to));
            to_header.get_style_context().remove_class("empty");
        }
        
        if (message.cc != null) {
            set_header_text(cc_header, format_addresses(message.cc));
            cc_header.get_style_context().remove_class("empty");
        }
        
        if (message.bcc != null) {
            set_header_text(bcc_header, format_addresses(message.bcc));
            bcc_header.get_style_context().remove_class("empty");
        }
        
        if (message.subject != null) {
            set_header_text(subject_header, message.subject.value);
            subject_header.get_style_context().remove_class("empty");
        }

        if (message.date != null) {
            Date.ClockFormat clock_format =
                GearyApplication.instance.config.clock_format;
            set_header_text(
                date_header,
                Date.pretty_print_verbose(message.date.value, clock_format)
            );
            date_header.get_style_context().remove_class("empty");
        }

        string preview_str = message.get_preview();
        preview_str = Geary.String.reduce_whitespace(preview_str);
        preview_label.set_text(preview_str);

        message_menubutton.set_menu_model(build_message_menu(email));
        message_menubutton.set_sensitive(false);

        web_view = new ConversationWebView();
        web_view.show();
        body_box.pack_end(web_view, true, true, 0);

        load_message_body();
        
        //Gtk.ScrolledWindow web_scroller = new Gtk.ScrolledWindow(null, null);
        //web_scroller.show();
        //web_scroller.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
        //web_scroller.add(web_view);
        //body_box.pack_end(web_scroller, true, true, 0);

        // web_view.hovering_over_link.connect(on_hovering_over_link);
        // web_view.context_menu.connect(() => { return true; }); // Suppress default context menu.
        // web_view.realize.connect( () => { web_view.get_vadjustment().value_changed.connect(mark_read); });
        // web_view.size_allocate.connect(mark_read);
        web_view.realize.connect(() => { debug("web_view: realised"); });
        web_view.size_allocate.connect(() => { debug("web_view: allocated"); });

        // web_view.link_selected.connect((link) => { link_selected(link); });
        
        // if (email.from != null && email.from.contains_normalized(current_account_information.email)) {
        //  // XXX set a RO property?
        //  get_style_context().add_class("sent");
        // }

        // // Set attachment icon and add the attachments container if there are displayed attachments.
        // int displayed = displayed_attachments(email);
        // set_attachment_icon(div_message, displayed > 0);
        // if (displayed > 0) {
        //     insert_attachments(div_message, email.attachments);
        // }
        
        // // Look for any attached emails
        // Gee.List<Geary.RFC822.Message> sub_messages = message.get_sub_messages();
        // foreach (Geary.RFC822.Message sub_message in sub_messages) {
        //     bool sub_remote_images = false;
        //     try {
        //         extra_part = set_message_html(
        //             sub_message, part_div, out sub_remote_images
        //         );
        //         extra_part.get_class_list().add("read");
        //         extra_part.get_class_list().add("hide");
        //         remote_images = remote_images || sub_remote_images;
        //     } catch (Error error) {
        //         debug("Error adding attached message: %s", error.message);
        //     }
        // }
        
        // // Edit draft button for drafts folder.
        // if (in_drafts_folder() && is_in_folder) {
        //     WebKit.DOM.HTMLElement draft_edit_container = Util.DOM.select(div_message, ".draft_edit");
        //     WebKit.DOM.HTMLElement draft_edit_button =
        //         Util.DOM.select(div_message, ".draft_edit_button");
        //     try {
        //         draft_edit_container.set_attribute("style", "display:block");
        //         draft_edit_button.set_inner_html(_("Edit Draft"));
        //     } catch (Error e) {
        //         warning("Error setting draft button: %s", e.message);
        //     }
        // }

        update_flags(email);

        message_overlay = new Gtk.Overlay();
        //message_overlay.add(conversation_viewer_scrolled);
        // composer_paned.pack1(message_overlay, true, false);
    }

    public bool is_message_visible() {
        return get_style_context().has_class("show-message");
    }

    public void show_message(bool include_transitions=true) {
        get_style_context().add_class("show-message");
        avatar_image.set_pixel_size(32); // XXX constant

        // XXX this is pretty gross
        Gtk.RevealerTransitionType revealer = from_revealer.get_transition_type();
        if (!include_transitions) {
            from_revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        from_revealer.set_reveal_child(true);
        from_revealer.set_transition_type(revealer);

        if (!to_header.get_style_context().has_class("empty")) {
            to_header.show();
        }
        if (!cc_header.get_style_context().has_class("empty")) {
            cc_header.show();
        }
        if (!bcc_header.get_style_context().has_class("empty")) {
            bcc_header.show();
        }
        if (!subject_header.get_style_context().has_class("empty")) {
            subject_header.show();
        }
        if (!date_header.get_style_context().has_class("empty")) {
            date_header.show();
        }
        preview_label.hide();
        flag_button.set_sensitive(true);
        message_menubutton.set_sensitive(true);

        // XXX this is pretty gross
        revealer = body_revealer.get_transition_type();
        if (!include_transitions) {
            body_revealer.set_transition_type(Gtk.RevealerTransitionType.NONE);
        }
        body_revealer.set_reveal_child(true);
        body_revealer.set_transition_type(revealer);
    }

    public void hide_message() {
        get_style_context().remove_class("show-message");
        avatar_image.set_pixel_size(24); // XXX constant
        from_revealer.set_reveal_child(false);
        to_header.hide();
        cc_header.hide();
        bcc_header.hide();
        subject_header.hide();
        date_header.hide();
        preview_label.show();
        flag_button.set_sensitive(false);
        message_menubutton.set_sensitive(false);
        body_revealer.set_reveal_child(false);
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
    }
    
    private MenuModel build_message_menu(Geary.Email email) {
        Gtk.Builder builder = new Gtk.Builder.from_resource(
            "/org/gnome/Geary/conversation-message-menu.ui"
        );

        MenuModel menu = (MenuModel) builder.get_object("conversation_message_menu");
        
        // menu.selection_done.connect(on_message_menu_selection_done);
        
        // int displayed = displayed_attachments(email);
        // if (displayed > 0) {
        //     string mnemonic = ngettext("Save A_ttachment...", "Save All A_ttachments...",
        //         displayed);
        //     Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(mnemonic);
        //     save_all_item.activate.connect(() => save_attachments(email.attachments));
        //     menu.append(save_all_item);
        //     menu.append(new Gtk.SeparatorMenuItem());
        // }
        
        // if (!in_drafts_folder()) {
        //     // Reply to a message.
        //     Gtk.MenuItem reply_item = new Gtk.MenuItem.with_mnemonic(_("_Reply"));
        //     reply_item.activate.connect(() => reply_to_message(email));
        //     menu.append(reply_item);

        //     // Reply to all on a message.
        //     Gtk.MenuItem reply_all_item = new Gtk.MenuItem.with_mnemonic(_("Reply to _All"));
        //     reply_all_item.activate.connect(() => reply_all_message(email));
        //     menu.append(reply_all_item);

        //     // Forward a message.
        //     Gtk.MenuItem forward_item = new Gtk.MenuItem.with_mnemonic(_("_Forward"));
        //     forward_item.activate.connect(() => forward_message(email));
        //     menu.append(forward_item);
        // }
        
        // if (menu.get_children().length() > 0) {
        //     // Separator.
        //     menu.append(new Gtk.SeparatorMenuItem());
        // }
        
        // // Mark as read/unread.
        // if (email.is_unread().to_boolean(false)) {
        //     Gtk.MenuItem mark_read_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Read"));
        //     mark_read_item.activate.connect(() => on_mark_read_message(email));
        //     menu.append(mark_read_item);
        // } else {
        //     Gtk.MenuItem mark_unread_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Unread"));
        //     mark_unread_item.activate.connect(() => on_mark_unread_message(email));
        //     menu.append(mark_unread_item);
            
        //     if (messages.size > 1 && messages.last() != email) {
        //         Gtk.MenuItem mark_unread_from_here_item = new Gtk.MenuItem.with_mnemonic(
        //             _("Mark Unread From _Here"));
        //         mark_unread_from_here_item.activate.connect(() => on_mark_unread_from_here(email));
        //         menu.append(mark_unread_from_here_item);
        //     }
        // }
        
        // // Print a message.
        // Gtk.MenuItem print_item = new Gtk.MenuItem.with_mnemonic(Stock._PRINT_MENU);
        // print_item.activate.connect(() => on_print_message(email));
        // menu.append(print_item);

        // // Separator.
        // menu.append(new Gtk.SeparatorMenuItem());

        // // View original message source.
        // Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("_View Source"));
        // view_source_item.activate.connect(() => on_view_source(email));
        // menu.append(view_source_item);

        return menu;
    }

    public void update_flags(Geary.Email email) {
        toggle_class("read");
        toggle_class("starred");
        
        //if (email.email_flags.is_outbox_sent()) {
        //  email_warning.set_inner_html(
        //      _("This message was sent successfully, but could not be saved to %s.").printf(
        //            Geary.SpecialFolderType.SENT.get_display_name()));
    }

    public void mark_manual_read() {
        get_style_context().add_class("manual_read");
    }

    // private void build_message_overlay_label(string? url) {
    //     message_overlay_label = new Gtk.Label(url);
    //     message_overlay_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
    //     message_overlay_label.halign = Gtk.Align.START;
    //     message_overlay_label.valign = Gtk.Align.END;
    //     //message_overlay_label.realize.connect(on_message_overlay_label_realize);
    //     message_overlay.add_overlay(message_overlay_label);
    // }

    private void load_message_body() {
        bool remote_images = false;
        string body_text = "";
        try {
            body_text = message.get_body(Geary.RFC822.TextFormat.HTML, inline_image_replacer) ?? "";
        } catch (Error err) {
            debug("Could not get message text. %s", err.message);
        }

        body_text = clean_html_markup(body_text, message, out remote_images);
        web_view.load_string(body_text, "text/html", "UTF8", "");

        // XXX The following will probably need to happen after the
        // message has been loaded.

        // if (remote_images) {
        //     Geary.Contact contact = containing_folder.account.get_contact_store().get_by_rfc822(
        //         email.get_primary_originator());
        //     bool always_load = contact != null && contact.always_load_remote_images();
            
        //     if (always_load || email.load_remote_images().is_certain()) {
        //         show_images_email(div_message, false);
        //     } else {
        //         WebKit.DOM.HTMLElement remote_images_bar =
        //             Util.DOM.select(div_message, ".remote_images");
        //         try {
        //             ((WebKit.DOM.Element) remote_images_bar).get_class_list().add("show");
        //             remote_images_bar.set_inner_html("""%s %s
        //                 <input type="button" value="%s" class="show_images" />
        //                 <input type="button" value="%s" class="show_from" />""".printf(
        //                 remote_images_bar.get_inner_html(),
        //                 _("This message contains remote images."), _("Show Images"),
        //                 _("Always Show From Sender")));
        //         } catch (Error error) {
        //             warning("Error showing remote images bar: %s", error.message);
        //         }
        //     }
        // }
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

    // private static void on_hide_quote_clicked(WebKit.DOM.Element element) {
    //     try {
    //         WebKit.DOM.Element parent = element.get_parent_element();
    //         parent.set_attribute("class", "quote_container controllable hide");
    //     } catch (Error error) {
    //         warning("Error hiding quote: %s", error.message);
    //     }
    // }

    // private static void on_show_quote_clicked(WebKit.DOM.Element element) {
    //     try {
    //         WebKit.DOM.Element parent = element.get_parent_element();
    //         parent.set_attribute("class", "quote_container controllable show");
    //     } catch (Error error) {
    //         warning("Error hiding quote: %s", error.message);
    //     }
    // }

    // private void on_unstar_clicked() {
    //  unflag_message();
    // }

    // private void on_star_clicked() {
    //  flag_message();
    // }

    // private bool is_hidden() {
    //  // XXX
    //  return false;
    // }

    // private void on_toggle_hidden() {
    //  // XXX
    //     get_viewer().mark_read();
    // }

    // private void on_show_images() {
    //  show_images(true);
    // }
    
    // private void on_show_images_from() {
    //     Geary.ContactStore contact_store =
    //         containing_folder.account.get_contact_store();
    //  Geary.Contact? contact = contact_store.get_by_rfc822(email.get_primary_originator());
    //     if (contact == null) {
    //         debug("Couldn't find contact for %s", email.from.to_string());
    //         return;
    //     }
        
    //     Geary.ContactFlags flags = new Geary.ContactFlags();
    //     flags.add(Geary.ContactFlags.ALWAYS_LOAD_REMOTE_IMAGES);
    //     Gee.ArrayList<Geary.Contact> contact_list = new Gee.ArrayList<Geary.Contact>();
    //     contact_list.add(contact);
    //     contact_store.mark_contacts_async.begin(contact_list, flags, null);
        
    //     WebKit.DOM.Document document = web_view.get_dom_document();
    //     try {
    //         WebKit.DOM.NodeList nodes = document.query_selector_all(".email");
    //         for (ulong i = 0; i < nodes.length; i ++) {
    //             WebKit.DOM.Element? email_element = nodes.item(i) as WebKit.DOM.Element;
    //             if (email_element != null) {
    //                 string? address = null;
    //                 WebKit.DOM.Element? address_el = email_element.query_selector(".address_value");
    //                 if (address_el != null) {
    //                     address = ((WebKit.DOM.HTMLElement) address_el).get_inner_text();
    //                 } else {
    //                     address_el = email_element.query_selector(".address_name");
    //                     if (address_el != null)
    //                         address = ((WebKit.DOM.HTMLElement) address_el).get_inner_text();
    //                 }
    //                 if (address != null && address.normalize().casefold() == contact.normalized_email)
    //                     show_images(false);
    //             }
    //         }
    //     } catch (Error error) {
    //         debug("Error showing images: %s", error.message);
    //     }
    // }
    
    // private void show_images(bool remember) {
    //  WebKit.DOM.Element email_element = get_email_element();
    //     try {
    //         WebKit.DOM.NodeList body_nodes = email_element.query_selector_all(".body");
    //         for (ulong j = 0; j < body_nodes.length; j++) {
    //             WebKit.DOM.Element? body = body_nodes.item(j) as WebKit.DOM.Element;
    //             if (body == null)
    //                 continue;
                
    //             WebKit.DOM.NodeList nodes = body.query_selector_all("img");
    //             for (ulong i = 0; i < nodes.length; i++) {
    //                 WebKit.DOM.Element? element = nodes.item(i) as WebKit.DOM.Element;
    //                 if (element == null || !element.has_attribute("src"))
    //                     continue;
                    
    //                 string src = element.get_attribute("src");
    //                 if (!web_view.is_always_loaded(src)) {
    //                     // Workaround a WebKitGTK+ 2.4.10 crash. See Bug 763933
    //                     element.remove_attribute("src");
    //                     element.set_attribute("src", web_view.allow_prefix + src);
    //                 }
    //             }
    //         }
            
    //         WebKit.DOM.Element? remote_images = email_element.query_selector(".remote_images");
    //         if (remote_images != null)
    //             remote_images.get_class_list().remove("show");
    //     } catch (Error error) {
    //         warning("Error showing images: %s", error.message);
    //     }
        
    //     if (remember) {
    //         // only add flag to load remote images if not already present
    //         if (email != null && !email.load_remote_images().is_certain()) {
    //             Geary.EmailFlags flags = new Geary.EmailFlags();
    //             flags.add(Geary.EmailFlags.LOAD_REMOTE_IMAGES);
    //             get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), flags, null);
    //         }
    //     }
    // }
    
    // private bool on_link_clicked_self(WebKit.DOM.Element element) {
    //     if (!Geary.String.is_empty(element.get_attribute("warning"))) {
    //         // A warning is open, so ignore clicks.
    //         return true;
    //     }
        
    //     string? href = element.get_attribute("href");
    //     if (Geary.String.is_empty(href))
    //         return false;
    //     string text = ((WebKit.DOM.HTMLElement) element).get_inner_text();
    //     string href_short, text_short;
    //     if (!deceptive_text(href, ref text, out href_short, out text_short))
    //         return false;
        
    //     WebKit.DOM.HTMLElement div = Util.DOM.clone_select(web_view.get_dom_document(),
    //         "#link_warning_template");
    //     try {
    //         div.set_inner_html("""%s %s <span><a href="%s">%s</a></span> %s
    //             <span><a href="%s">%s</a></span>""".printf(div.get_inner_html(),
    //             _("This link appears to go to"), text, text_short,
    //             _("but actually goes to"), href, href_short));
    //         div.remove_attribute("id");
    //         element.parent_node.insert_before(div, element);
    //         element.set_attribute("warning", "open");
            
    //         long overhang = div.get_offset_left() + div.get_offset_width() -
    //             web_view.get_dom_document().get_body().get_offset_width();
    //         if (overhang > 0)
    //             div.set_attribute("style", @"margin-left: -$(overhang)px;");
    //     } catch (Error error) {
    //         warning("Error showing link warning dialog: %s", error.message);
    //     }
    //     bind_event(web_view, ".link_warning .close_link_warning, .link_warning a", "click",
    //         (Callback) on_close_link_warning, this);
    //     return true;
    // }
    
    // private void on_close_link_warning(WebKit.DOM.Element element, WebKit.DOM.Event event,
    //     ConversationMessage conversation_message) {
    //     try {
    //         WebKit.DOM.Element warning_div = closest_ancestor(element, ".link_warning");
    //         WebKit.DOM.Element link = (WebKit.DOM.Element) warning_div.get_next_sibling();
    //         link.remove_attribute("warning");
    //         warning_div.parent_node.remove_child(warning_div);
    //     } catch (Error error) {
    //         warning("Error removing link warning dialog: %s", error.message);
    //     }
    // }

    // private void on_draft_edit_menu() {
    //     get_viewer().edit_draft(email);
    // }
    
    // /*
    //  * Test whether text looks like a URI that leads somewhere other than href.  The text
    //  * will have a scheme prepended if it doesn't already have one, and the short versions
    //  * have the scheme skipped and long paths truncated.
    //  */
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
    
    // private void on_attachment_clicked(string attachment_id) {
    //     Geary.Attachment? attachment = null;
    //     try {
    //         attachment = email.get_attachment(attachment_id);
    //     } catch (Error error) {
    //         warning("Error opening attachment: %s", error.message);
    //     }
        
    //     if (attachment != null) {
    //         get_viewer().open_attachment(attachment);
    //  }
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
    
    // private void save_attachment(Geary.Attachment attachment) {
    //     Gee.List<Geary.Attachment> attachments = new Gee.ArrayList<Geary.Attachment>();
    //     attachments.add(attachment);
    //     get_viewer().save_attachments(attachments);
    // }
    
    // private void on_mark_read_message(Geary.Email message) {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.UNREAD);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), null, flags);
    //     mark_manual_read(message.id);
    // }

    // private void on_mark_unread_message(Geary.Email message) {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.UNREAD);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(message.id).to_array_list(), flags, null);
    //     mark_manual_read(message.id);
    // }
    
    // private void on_mark_unread_from_here(Geary.Email message) {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.UNREAD);
        
    //     Gee.Iterator<Geary.Email>? iter = messages.iterator_at(message);
    //     if (iter == null) {
    //         warning("Email not found in message list");
            
    //         return;
    //     }
        
    //     // Build a list of IDs to mark.
    //     Gee.ArrayList<Geary.EmailIdentifier> to_mark = new Gee.ArrayList<Geary.EmailIdentifier>();
    //     to_mark.add(message.id);
    //     while (iter.next())
    //         to_mark.add(iter.get().id);
        
    //     get_viewer().mark_messages(to_mark, flags, null);
    //     foreach(Geary.EmailIdentifier id in to_mark)
    //         mark_manual_read(id);
    // }
    
    // private void on_print_message(Geary.Email message) {
    //     try {
    //         email_to_element.get(message.id).get_class_list().add("print");
    //         web_view.get_main_frame().print();
    //         email_to_element.get(message.id).get_class_list().remove("print");
    //     } catch (GLib.Error error) {
    //         debug("Hiding elements for printing failed: %s", error.message);
    //     }
    // }
    
    // private void flag_message() {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.FLAGGED);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), flags, null);
    // }

    // private void unflag_message() {
    //     Geary.EmailFlags flags = new Geary.EmailFlags();
    //     flags.add(Geary.EmailFlags.FLAGGED);
    //     get_viewer().mark_messages(Geary.iterate<Geary.EmailIdentifier>(email.id).to_array_list(), null, flags);
    // }

    // private void show_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
    //     attachment_menu = build_attachment_menu(email, attachment);
    //     attachment_menu.show_all();
    //     attachment_menu.popup(null, null, null, 0, Gtk.get_current_event_time());
    // }
    
    // private Gtk.Menu build_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
    //     Gtk.Menu menu = new Gtk.Menu();
    //     menu.selection_done.connect(on_attachment_menu_selection_done);
        
    //     Gtk.MenuItem save_attachment_item = new Gtk.MenuItem.with_mnemonic(_("_Save As..."));
    //     save_attachment_item.activate.connect(() => save_attachment(attachment));
    //     menu.append(save_attachment_item);
        
    //     if (displayed_attachments(email) > 1) {
    //         Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(_("Save All A_ttachments..."));
    //         save_all_item.activate.connect(() => save_attachments(email.attachments));
    //         menu.append(save_all_item);
    //     }
        
    //     return menu;
    // }

    private WebKit.DOM.HTMLDivElement create_quote_container() throws Error {
        WebKit.DOM.HTMLDivElement quote_container = web_view.create_div();
        quote_container.set_attribute("class", "quote_container controllable hide");
        quote_container.set_inner_html(
            """<div class="shower"><input type="button" value="▼        ▼        ▼" /></div>""" +
            """<div class="hider"><input type="button" value="▲        ▲        ▲" /></div>""" +
            """<div class="quote"></div>""");
        return quote_container;
    }

    // private void unset_controllable_quotes(WebKit.DOM.HTMLElement element) throws GLib.Error {
    //     WebKit.DOM.NodeList quote_list = element.query_selector_all(".quote_container.controllable");
    //     for (int i = 0; i < quote_list.length; ++i) {
    //         WebKit.DOM.Element quote_container = quote_list.item(i) as WebKit.DOM.Element;
    //         long scroll_height = quote_container.query_selector(".quote").scroll_height;
    //         // If the message is hidden, scroll_height will be 0.
    //         if (scroll_height > 0 && scroll_height < QUOTE_SIZE_THRESHOLD) {
    //             quote_container.set_attribute("class", "quote_container");
    //         }
    //     }
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
    
    // private bool should_show_attachment(Geary.Attachment attachment) {
    //     // if displayed inline, don't include in attachment list
    //     if (attachment.content_id in inlined_content_ids)
    //         return false;
        
    //     switch (attachment.content_disposition.disposition_type) {
    //         case Geary.Mime.DispositionType.ATTACHMENT:
    //             return true;
            
    //         case Geary.Mime.DispositionType.INLINE:
    //             return !is_content_type_supported_inline(attachment.content_type);
            
    //         default:
    //             assert_not_reached();
    //     }
    // }
    
    // private int displayed_attachments(Geary.Email email) {
    //     int ret = 0;
    //     foreach (Geary.Attachment attachment in email.attachments) {
    //         if (should_show_attachment(attachment)) {
    //             ret++;
    //         }
    //     }
    //     return ret;
    // }
    
    // private void insert_attachments(WebKit.DOM.HTMLElement email_container,
    //     Gee.List<Geary.Attachment> attachments) {

    //     // <div class="attachment_container">
    //     //     <div class="top_border"></div>
    //     //     <table class="attachment" data-attachment-id="">
    //     //         <tr>
    //     //             <td class="preview">
    //     //                 <img src="" />
    //     //             </td>
    //     //             <td class="info">
    //     //                 <div class="filename"></div>
    //     //                 <div class="filesize"></div>
    //     //             </td>
    //     //         </tr>
    //     //     </table>
    //     // </div>

    //     try {
    //         // Prepare the dom for our attachments.
    //         WebKit.DOM.Document document = web_view.get_dom_document();
    //         WebKit.DOM.HTMLElement attachment_container =
    //             Util.DOM.clone_select(document, "#attachment_template");
    //         WebKit.DOM.HTMLElement attachment_template =
    //             Util.DOM.select(attachment_container, ".attachment");
    //         attachment_container.remove_attribute("id");
    //         attachment_container.remove_child(attachment_template);

    //         // Create an attachment table for each attachment.
    //         foreach (Geary.Attachment attachment in attachments) {
    //             if (!should_show_attachment(attachment)) {
    //                 continue;
    //             }
    //             // Generate the attachment table.
    //             WebKit.DOM.HTMLElement attachment_table = Util.DOM.clone_node(attachment_template);
    //             string filename = !attachment.has_supplied_filename ? _("none") : attachment.file.get_basename();
    //             Util.DOM.select(attachment_table, ".info .filename")
    //                 .set_inner_text(filename);
    //             Util.DOM.select(attachment_table, ".info .filesize")
    //                 .set_inner_text(Files.get_filesize_as_string(attachment.filesize));
    //             attachment_table.set_attribute("data-attachment-id", attachment.id);

    //             // Set the image preview and insert it into the container.
    //             WebKit.DOM.HTMLImageElement img =
    //                 Util.DOM.select(attachment_table, ".preview img") as WebKit.DOM.HTMLImageElement;
    //             web_view.set_attachment_src(img, attachment.content_type, attachment.file.get_path(),
    //                 ATTACHMENT_PREVIEW_SIZE);
    //             attachment_container.append_child(attachment_table);
    //         }

    //         // Append the attachments to the email.
    //         email_container.append_child(attachment_container);
    //     } catch (Error error) {
    //         debug("Failed to insert attachments: %s", error.message);
    //     }
    // }
    
    // private bool in_drafts_folder() {
    //     return containing_folder.special_folder_type == Geary.SpecialFolderType.DRAFTS;
    // }

    private void toggle_class(string cls) {
        Gtk.StyleContext context = get_style_context();
        if (context.has_class(cls)) {
            context.add_class(cls);
        } else {
            context.remove_class(cls);
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
    
    // private void on_hovering_over_link(string? title, string? url) {
    //     // Copy the link the user is hovering over.  Note that when the user mouses-out, 
    //     // this signal is called again with null for both parameters.
    //     hover_url = url != null ? Uri.unescape_string(url) : null;
        
    //     if (message_overlay_label == null) {
    //         if (url == null)
    //             return;
    //         build_message_overlay_label(Uri.unescape_string(url));
    //         message_overlay_label.show();
    //         return;
    //     }
        
    //     if (url == null) {
    //         message_overlay_label.hide();
    //         message_overlay_label.label = null;
    //     } else {
    //         message_overlay_label.show();
    //         message_overlay_label.label = Uri.unescape_string(url);
    //     }
    // }
    
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
    
    // private void on_view_source(Geary.Email message) {
    //     string source = message.header.buffer.to_string() + message.body.buffer.to_string();
        
    //     try {
    //         string temporary_filename;
    //         int temporary_handle = FileUtils.open_tmp("geary-message-XXXXXX.txt",
    //             out temporary_filename);
    //         FileUtils.set_contents(temporary_filename, source);
    //         FileUtils.close(temporary_handle);
            
    //         // ensure this file is only readable by the user ... this needs to be done after the
    //         // file is closed
    //         FileUtils.chmod(temporary_filename, (int) (Posix.S_IRUSR | Posix.S_IWUSR));
            
    //         string temporary_uri = Filename.to_uri(temporary_filename, null);
    //         Gtk.show_uri(web_view.get_screen(), temporary_uri, Gdk.CURRENT_TIME);
    //     } catch (Error error) {
    //         ErrorDialog dialog = new ErrorDialog(GearyApplication.instance.controller.main_window,
    //             _("Failed to open default text editor."), error.message);
    //         dialog.run();
    //     }
    // }

}
