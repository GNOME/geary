/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class MessageViewer : WebKit.WebView {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.FLAGS
        | Geary.Email.Field.PREVIEW;
    
    public const string USER_CSS = "user-message.css";
    
    private const int ATTACHMENT_PREVIEW_SIZE = 50;
    private const string MESSAGE_CONTAINER_ID = "message_container";
    private const string SELECTION_COUNTER_ID = "multiple_messages";
    private const string STYLE_NAME = "STYLE";
    
    private const string MAILTO_SCHEME = "mailto:";
    
    // Fired when the user clicks a link.
    public signal void link_selected(string link);
    
    // Fired when the user hovers over or stops hovering over a link.
    public signal void link_hover(string? link);

    // Fired when the user clicks "reply" in the message menu.
    public signal void reply_to_message(Geary.Email message);

    // Fired when the user clicks "reply all" in the message menu.
    public signal void reply_all_message(Geary.Email message);

    // Fired when the user clicks "forward" in the message menu.
    public signal void forward_message(Geary.Email message);

    // Fired when the user marks a message.
    public signal void mark_message(Geary.Email message, Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);

    // Fired when the user opens an attachment.
    public signal void open_attachment(Geary.Attachment attachment);

    // Fired when the user wants to save one or more attachments.
    public signal void save_attachments(Gee.List<Geary.Attachment> attachment);

    // List of emails in this view.
    public Gee.TreeSet<Geary.Email> messages { get; private set; default = 
        new Gee.TreeSet<Geary.Email>((CompareFunc<Geary.Email>) Geary.Email.compare_date_ascending); }
    
    // HTML element that contains message DIVs.
    private WebKit.DOM.HTMLDivElement container;
    
    // Maps emails to their corresponding elements.
    private Gee.HashMap<Geary.EmailIdentifier, WebKit.DOM.HTMLElement> email_to_element = new
        Gee.HashMap<Geary.EmailIdentifier, WebKit.DOM.HTMLElement>(Geary.Hashable.hash_func,
        Geary.Equalable.equal_func);
    
    private int width = 0;
    private int height = 0;
    private string? hover_url = null;
    private Gtk.Menu? context_menu = null;
    private Gtk.Menu? message_menu = null;
    private Gtk.Menu? attachment_menu = null;
    private FileMonitor? user_style_monitor = null;
    private weak Geary.Folder? current_folder = null;
    
    public MessageViewer() {
        valign = Gtk.Align.START;
        vexpand = true;
        set_border_width(0);
        
        navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        parent_set.connect(on_parent_set);
        hovering_over_link.connect(on_hovering_over_link);
        resource_request_starting.connect(on_resource_request_starting);
        
        WebKit.WebSettings s = new WebKit.WebSettings();
        s.enable_default_context_menu = false;
        s.enable_scripts = false;
        s.enable_java_applet = false;
        s.enable_plugins = false;
        settings = s;
        
        // Load the HTML into WebKit.
        load_finished.connect(on_load_finished);
        string html_text = GearyApplication.instance.read_theme_file("message-viewer.html") ?? "";
        load_string(html_text, "text/html", "UTF8", "");
    }
    
    private void on_load_finished(WebKit.WebFrame frame) {
        // Load the style.
        try {
            WebKit.DOM.Document document = get_dom_document();
            WebKit.DOM.Element style_element = document.create_element(STYLE_NAME);

            string css_text = GearyApplication.instance.read_theme_file("message-viewer.css") ?? "";
            WebKit.DOM.Text text_node = document.create_text_node(css_text);
            style_element.append_child(text_node);

            WebKit.DOM.HTMLHeadElement head_element = document.get_head();
            head_element.append_child(style_element);
        } catch (Error error) {
            debug("Unable to load message-viewer document from files: %s", error.message);
        }

        load_user_style();

        // Grab the HTML container.
        WebKit.DOM.Element? _container = get_dom_document().get_element_by_id("message_container");
        assert(_container != null);
        container = _container as WebKit.DOM.HTMLDivElement;
        assert(container != null);

        // Load the icons.
        set_icon_src("#email_template .menu .icon", "down");
        set_icon_src("#email_template .starred .icon", "starred");
        set_icon_src("#email_template .unstarred .icon", "non-starred-grey");
        set_icon_src("#email_template .attachment.icon", "mail-attachment");
    }
    
    private void on_resource_request_starting(WebKit.WebFrame web_frame,
        WebKit.WebResource web_resource, WebKit.NetworkRequest request,
        WebKit.NetworkResponse? response) {

        if (!request.get_uri().has_prefix("http://www.gravatar.com/avatar/")
         && !request.get_uri().has_prefix("data:")) {
            request.set_uri("about:blank");
        }
    }

    private void load_user_style() {
        try {
            WebKit.DOM.Document document = get_dom_document();
            WebKit.DOM.Element style_element = document.create_element(STYLE_NAME);
            style_element.set_attribute("id", "user_style");
            WebKit.DOM.HTMLHeadElement head_element = document.get_head();
            head_element.append_child(style_element);
            
            File user_style = GearyApplication.instance.get_user_config_directory().get_child(USER_CSS);
            user_style_monitor = user_style.monitor_file(FileMonitorFlags.NONE, null);
            user_style_monitor.changed.connect(on_user_style_changed);
            
            // And call it once to load the initial user style
            on_user_style_changed(user_style, null, FileMonitorEvent.CREATED);
        } catch (Error error) {
            debug("Error setting up user style: %s", error.message);
        }
    }

    private void on_user_style_changed(File user_style, File? other_file, FileMonitorEvent event_type) {
        // Changing a file produces 1 created signal, 3 changes done hints, and 0 changed
        if (event_type != FileMonitorEvent.CHANGED && event_type != FileMonitorEvent.CREATED
            && event_type != FileMonitorEvent.DELETED) {
            return;
        }
        
        debug("Loading new message viewer style from %s...", user_style.get_path());
        
        WebKit.DOM.Document document = get_dom_document();
        WebKit.DOM.Element style_element = document.get_element_by_id("user_style");
        ulong n = style_element.child_nodes.length;
        try {
            for (int i = 0; i < n; i++)
                style_element.remove_child(style_element.first_child);
        } catch (Error error) {
            debug("Error removing old user style: %s", error.message);
        }
        
        try {
            DataInputStream data_input_stream = new DataInputStream(user_style.read());
            size_t length;
            string user_css = data_input_stream.read_upto("\0", 1, out length);
            WebKit.DOM.Text text_node = document.create_text_node(user_css);
            style_element.append_child(text_node);
        } catch (Error error) {
            // Expected if file was deleted.
        }
    }

    private void set_icon_src(string selector, string icon_name) {
        try {
            // Load the icon.
            string icon_filename = IconFactory.instance.lookup_icon(icon_name, 16).get_filename();
            uint8[] icon_content;
            FileUtils.get_data(icon_filename, out icon_content);

            // Fetch its mime type.
            bool uncertain_content_type;
            string icon_mimetype = ContentType.get_mime_type(ContentType.guess(icon_filename,
                icon_content, out uncertain_content_type));

            // Then set the source to a data url.
            WebKit.DOM.HTMLImageElement img = Util.DOM.select(get_dom_document(), selector)
                as WebKit.DOM.HTMLImageElement;
            set_data_url(img, icon_mimetype, icon_content);
        } catch (Error error) {
            warning("Failed to load icon '%s': %s", icon_name, error.message);
        }
    }

    private void set_image_src(WebKit.DOM.HTMLImageElement img, string mime_type, string filename,
        int maxwidth, int maxheight = -1) {
        if( maxheight == -1 ){
            maxheight = maxwidth;
        }

        try {
            // If the file is an image, use it. Otherwise get the icon for this mime_type.
            uint8[] content;
            string content_type = ContentType.from_mime_type(mime_type);
            string icon_mime_type = mime_type;
            if (mime_type.has_prefix("image/")) {
                // Get a thumbnail for the image.
                // TODO Generate and save the thumbnail when extracting the attachments rather than
                // when showing them in the viewer.
                img.get_class_list().add("thumbnail");
                Gdk.Pixbuf image = new Gdk.Pixbuf.from_file_at_scale(filename, maxwidth, maxheight,
                    true);
                image.save_to_buffer(out content, "png");
                icon_mime_type = "image/png";
            } else {
                // Load the icon for this mime type.
                ThemedIcon icon = ContentType.get_icon(content_type) as ThemedIcon;
                string icon_filename = IconFactory.instance.lookup_icon(icon.names[0], maxwidth)
                    .get_filename();
                FileUtils.get_data(icon_filename, out content);
                icon_mime_type = ContentType.get_mime_type(ContentType.guess(icon_filename, content,
                    null));
            }

            // Then set the source to a data url.
            set_data_url(img, icon_mime_type, content);
        } catch (Error error) {
            warning("Failed to load image '%s': %s", filename, error.message);
        }
    }

    private void set_data_url(WebKit.DOM.HTMLImageElement img, string mime_type, uint8[] content)
        throws Error {
        img.set_attribute("src", "data:%s;base64,%s".printf(mime_type, Base64.encode(content)));
    }
    
    public Geary.Email? get_last_message() {
        return messages.is_empty ? null : messages.last();
    }
    
    // Removes all displayed e-mails from the view.
    public void clear(Geary.Folder? new_folder) {
        // Remove all messages from DOM.
        try {
            foreach (WebKit.DOM.HTMLElement element in email_to_element.values) {
                if (element.get_parent_element() != null)
                    element.get_parent_element().remove_child(element);
            }
        } catch (Error e) {
            debug("Error clearing message viewer: %s", e.message);
        }
        email_to_element.clear();
        messages.clear();
        
        current_folder = new_folder;
    }
    
    // Converts an email ID into HTML ID used by the <div> for the email.
    private string get_div_id(Geary.EmailIdentifier id) {
        return "message_%s".printf(id.to_string());
    }
    
    private void hide_element_by_id(string element_id) throws Error {
        get_dom_document().get_element_by_id(element_id).set_attribute("style", "display:none");
    }

    private void show_element_by_id(string element_id) throws Error {
        get_dom_document().get_element_by_id(element_id).set_attribute("style", "display:block");
    }
    
    public void show_multiple_selected(uint selected_count) {
        // Remove any messages and hide the message container, then show the counter.
        clear(current_folder);
        try {
            hide_element_by_id(MESSAGE_CONTAINER_ID);
            show_element_by_id(SELECTION_COUNTER_ID);
            
            // Update the counter's count.
            WebKit.DOM.HTMLElement counter =
                get_dom_document().get_element_by_id("selection_counter") as WebKit.DOM.HTMLElement;
            if (selected_count == 0) {
                counter.set_inner_html(_("No conversations selected."));
            } else {
                counter.set_inner_html(_("%u conversations selected.").printf(selected_count));
            }
        } catch (Error e) {
            debug("Error updating counter: %s", e.message);
        }
    }
    
    public void add_message(Geary.Email email) {
        // Make sure the message container is showing and the multi-message counter hidden.
        try {
            show_element_by_id(MESSAGE_CONTAINER_ID);
            hide_element_by_id(SELECTION_COUNTER_ID);
        } catch (Error e) {
            debug("Error showing/hiding containers: %s", e.message);
        }

        if (messages.contains(email))
            return;
        
        string message_id = get_div_id(email.id);
        string header = "";
        
        WebKit.DOM.Node insert_before = container.get_last_child();
        
        messages.add(email);
        Geary.Email? higher = messages.higher(email);
        if (higher != null)
            insert_before = get_dom_document().get_element_by_id(get_div_id(higher.id));
        
        WebKit.DOM.HTMLElement div_email_container;
        WebKit.DOM.HTMLElement div_message;
        try {
            // The HTML is like this:
            // <div id="$MESSAGE_ID" class="email">
            //     <div class="geary_spacer"></div>
            //     <div class="email_container">
            //         <div class="button_bar">
            //             <div class="starred button"><img class="icon" /></div>
            //             <div class="unstarred button"><img class="icon" /></div>
            //             <div class="menu button"><img class="icon" /></div>
            //         </div>
            //         <table>$HEADER</table>
            //         <span>
            //             $EMAIL_BODY
            //
            //             <div class="signature">$SIGNATURE</div>
            //
            //             <div class="quote_container controllable">
            //                 <div class="shower">[show]</div>
            //                 <div class="hider">[hide]</div>
            //                 <div class="quote">$QUOTE</div>
            //             </div>
            //         </span>
            //     </div>
            // </div>
            div_message = Util.DOM.clone_select(get_dom_document(), "#email_template");
            div_message.set_attribute("id", message_id);
            container.insert_before(div_message, insert_before);
            div_email_container = Util.DOM.select(div_message, "div.email_container");
            if (email.is_unread() == Geary.Trillian.FALSE) {
                div_message.get_class_list().add("hide");
            }
        } catch (Error setup_error) {
            warning("Error setting up webkit: %s", setup_error.message);
            
            return;
        }
        
        email_to_element.set(email.id, div_message);
        
        string username;
        try {
            // TODO: Multiple accounts.
            username = Geary.Engine.get_usernames().get(0);
        } catch (Error e) {
            error("Unable to get username. Error: %s", e.message);
        }
        
        insert_header_address(ref header, _("From:"), email.from != null ? email.from : email.sender,
            true);
        
        // Only include to string if it's not just this account.
        // TODO: multiple accounts.
        if (email.to != null) {
            if (!(email.to.get_all().size == 1 && email.to.get_all().get(0).address == username))
                 insert_header_address(ref header, _("To:"), email.to);
        }

        if (email.cc != null) {
            insert_header_address(ref header, _("Cc:"), email.cc);
        }

        if (email.bcc != null) {
            insert_header_address(ref header, _("Bcc:"), email.bcc);
        }
            
        if (email.subject != null)
            insert_header(ref header, _("Subject:"), email.get_subject_as_string());
            
        if (email.date != null)
            insert_header_date(ref header, _("Date:"), email.date.value, true);

        // Add the avatar.
        Geary.RFC822.MailboxAddress? primary = email.get_primary_originator();
        if (primary != null) {
            try {
                WebKit.DOM.HTMLImageElement icon = Util.DOM.select(div_message, ".avatar")
                    as WebKit.DOM.HTMLImageElement;
                icon.set_attribute("src",
                    Gravatar.get_image_uri(primary, Gravatar.Default.MYSTERY_MAN, 48));
            } catch (Error error) {
                warning("Failed to load avatar: %s", error.message);
            }
        }
        
        // Insert the preview text.
        try {
            WebKit.DOM.HTMLElement preview =
                Util.DOM.select(div_message, ".header_container .preview");
            string preview_str = email.get_preview_as_string();
            if (preview_str.length == Geary.Email.MAX_PREVIEW_BYTES) {
                preview_str += "…";
            }
            preview.set_inner_text(Geary.String.reduce_whitespace(preview_str));
        } catch (Error error) {
            debug("Failed to add preview text: %s", error.message);
        }

        string body_text = "";
        try {
            body_text = email.get_message().get_first_mime_part_of_content_type("text/html").to_string();
            body_text = insert_html_markup(body_text, email);
        } catch (Error err) {
            try {
                body_text = linkify_and_escape_plain_text(email.get_message().
                    get_first_mime_part_of_content_type("text/plain").to_string());
                body_text = insert_plain_text_markup(body_text);
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }

        // Graft header and email body into the email container.
        try {
            WebKit.DOM.HTMLElement table_header =
                Util.DOM.select(div_email_container, ".header_container .header");
            table_header.set_inner_html(header);
            
            WebKit.DOM.HTMLElement span_body = Util.DOM.select(div_email_container, ".body");
            span_body.set_inner_html(body_text);

        } catch (Error html_error) {
            warning("Error setting HTML for message: %s", html_error.message);
        }

        // Add the attachments container if we have any attachments.
        if (email.attachments.size > 0) {
            insert_attachments(div_message, email.attachments);
        }

        // Add classes according to the state of the email.
        update_flags(email);

        // Attach to the click events for hiding/showing quotes, opening the menu, and so forth.
        bind_event(this, ".email", "contextmenu", (Callback) on_context_menu, this);
        bind_event(this, ".quote_container > .hider", "click", (Callback) on_hide_quote_clicked);
        bind_event(this, ".quote_container > .shower", "click", (Callback) on_show_quote_clicked);
        bind_event(this, ".email_container .menu", "click", (Callback) on_menu_clicked, this);
        bind_event(this, ".email_container .starred", "click", (Callback) on_unstar_clicked, this);
        bind_event(this, ".email_container .unstarred", "click", (Callback) on_star_clicked, this);
        bind_event(this, ".header .field .value", "click", (Callback) on_value_clicked, this);
        bind_event(this, ".email .header_container", "click", (Callback) on_body_toggle_clicked, this);
        bind_event(this, ".attachment_container .attachment", "click", (Callback) on_attachment_clicked, this);
        bind_event(this, ".attachment_container .attachment", "contextmenu", (Callback) on_attachment_menu, this);
    }
        
    public void unhide_last_email() {
        WebKit.DOM.HTMLElement last_email = (WebKit.DOM.HTMLElement) container.get_last_child().previous_sibling;
        if (last_email != null) {
            WebKit.DOM.DOMTokenList class_list = last_email.get_class_list();
            try {
                class_list.remove("hide");
            } catch (Error error) {
                // Expected, if not hidden
            }
        }
    }
    
    private WebKit.DOM.HTMLElement? closest_ancestor(WebKit.DOM.Element element, string selector) {
        try {
            WebKit.DOM.Element? parent = element.get_parent_element();
            while (parent != null && !parent.webkit_matches_selector(selector)) {
                parent = parent.get_parent_element();
            }
            return parent as WebKit.DOM.HTMLElement;
        } catch (Error error) {
            warning("Failed to find ancestor: %s", error.message);
            return null;
        }
    }

    private Geary.Email? get_email_from_element(WebKit.DOM.Element element) {
        // First get the email container.
        WebKit.DOM.Element? email_element = null;
        try {
            if (element.webkit_matches_selector(".email")) {
                email_element = element;
            } else {
                email_element = closest_ancestor(element, ".email");
            }
        } catch (Error error) {
            debug("Failed to find div.email from element: %s", error.message);
            return null;
        }
        
        if (email_element == null)
            return null;
        
        // Next find the ID in the email-to-element map.
        Geary.EmailIdentifier? email_id = null;
        foreach (var entry in email_to_element.entries) {
            if (entry.value == email_element) {
                email_id = entry.key;
                break;
            }
        }
        
        if (email_id == null)
            return null;

        // Now lookup the email in our messages set.
        foreach (Geary.Email message in messages) {
            if (message.id == email_id)
                return message;
        }
        
        return null;
    }
    
    private Geary.Attachment? get_attachment_from_element(WebKit.DOM.Element element) {
        Geary.Email? email = get_email_from_element(element);
        if (email == null)
            return null;
         
        try {
            return email.get_attachment(int64.parse(element.get_attribute("data-attachment-id")));
        } catch (Geary.EngineError err) {
            return null;
        }
    }

    public void update_flags(Geary.Email email) {
        // Nothing to do if we aren't displaying this email.
        if (!email_to_element.has_key(email.id)) {
            return;
        }

        Geary.EmailFlags flags = email.email_flags;
        
        // Update the flags in our message set.
        foreach (Geary.Email message in messages) {
            if (message.id.equals(email.id)) {
                message.set_flags(flags);
                break;
            }
        }
        
        // Get the email div and update its state.
        WebKit.DOM.HTMLElement container = email_to_element.get(email.id);
        try {
            WebKit.DOM.DOMTokenList class_list = container.get_class_list();
            Util.DOM.toggle_class(class_list, "read", !flags.is_unread());
            Util.DOM.toggle_class(class_list, "starred", flags.is_flagged());
            Util.DOM.toggle_class(class_list, "attachment", email.attachments.size > 0);
        } catch (Error e) {
            warning("Failed to set classes on .email: %s", e.message);
        }
    }

    private static void on_context_menu(WebKit.DOM.Element clicked_element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        Geary.Email email = message_viewer.get_email_from_element(clicked_element);
        if (email != null)
            message_viewer.show_context_menu(email);
    }
    
    private void show_context_menu(Geary.Email email) {
        context_menu = build_context_menu(email);
        context_menu.show_all();
        context_menu.popup(null, null, null, 0, 0);
    }
    
    private Gtk.Menu build_context_menu(Geary.Email email) {
        Gtk.Menu menu = new Gtk.Menu();
        
        if (can_copy_clipboard()) {
            // Add a menu item for copying the current selection.
            Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("_Copy"));
            item.activate.connect(on_copy_text);
            menu.append(item);
        }
        
        if (hover_url != null) {
            // Add a menu item for copying the link.
            Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("Copy _Link"));
            item.activate.connect(on_copy_link);
            menu.append(item);
            
            if (Geary.RFC822.MailboxAddress.is_valid_address(hover_url)) {
                // Add a menu item for copying the address.
                item = new Gtk.MenuItem.with_mnemonic(_("Copy _Email Address"));
                item.activate.connect(on_copy_email_address);
                context_menu.append(item);
            }
        }
        
        // View original message source
        Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("View _Source"));
        view_source_item.activate.connect(() => on_view_source(email));
        menu.append(view_source_item);

        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(_("Select _All"));
        select_all_item.activate.connect(on_select_all);
        menu.append(select_all_item);
        
        return menu;
    }

    private static void on_hide_quote_clicked(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.Element parent = element.get_parent_element();
            parent.set_attribute("class", "quote_container controllable hide");
        } catch (Error error) {
            warning("Error hiding quote: %s", error.message);
        }
    }

    private static void on_show_quote_clicked(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.Element parent = element.get_parent_element();
            parent.set_attribute("class", "quote_container controllable show");
        } catch (Error error) {
            warning("Error hiding quote: %s", error.message);
        }
    }

    private static void on_menu_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        event.stop_propagation();
        Geary.Email email = message_viewer.get_email_from_element(element);
        if (email != null)
            message_viewer.show_message_menu(email);
    }

    private static void on_unstar_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        event.stop_propagation();
        Geary.Email? email = message_viewer.get_email_from_element(element);
        if (email != null)
            message_viewer.unflag_message(email);
    }

    private static void on_star_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        event.stop_propagation();
        Geary.Email? email = message_viewer.get_email_from_element(element);
        if (email != null)
            message_viewer.flag_message(email);
    }

    private static void on_value_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        if (!message_viewer.is_hidden_email(element))
            event.stop_propagation();  // Don't allow toggle
    }

    private bool is_hidden_email(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.HTMLElement? email_element = closest_ancestor(element, ".email");
            if (email_element == null)
                return false;
            
            WebKit.DOM.DOMTokenList class_list = email_element.get_class_list();
            return class_list.contains("hide");
        } catch (Error error) {
            warning("Error getting hidden status: %s", error.message);
            return false;
        }
    }

    private static void on_body_toggle_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        message_viewer.on_body_toggle_clicked_self(element);
    }

    private void on_body_toggle_clicked_self(WebKit.DOM.Element element) {
        try {
            WebKit.DOM.HTMLElement? email_element = closest_ancestor(element, ".email");
            if (email_element == null)
                return;
            
            WebKit.DOM.DOMTokenList class_list = email_element.get_class_list();
            if (class_list.contains("hide"))
                class_list.remove("hide");
            else
                class_list.add("hide");
        } catch (Error error) {
            warning("Error toggling message: %s", error.message);
        }
    }

    private static void on_attachment_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        message_viewer.on_attachment_clicked_self(element);
    }

    private void on_attachment_clicked_self(WebKit.DOM.Element element) {
        int64 attachment_id = int64.parse(element.get_attribute("data-attachment-id"));
        Geary.Email? email = get_email_from_element(element);
        if (email == null)
            return;
        
        Geary.Attachment? attachment = null;
        try {
            attachment = email.get_attachment(attachment_id);
        } catch (Error error) {
            warning("Error opening attachment: %s", error.message);
        }
        
        if (attachment != null)
            open_attachment(attachment);
    }

    private static void on_attachment_menu(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        event.stop_propagation();
        Geary.Email? email = message_viewer.get_email_from_element(element);
        Geary.Attachment? attachment = message_viewer.get_attachment_from_element(element);
        if (email != null && attachment != null)
            message_viewer.show_attachment_menu(email, attachment);
    }
    
    private void on_message_menu_selection_done() {
        message_menu = null;
    }
    
    private void on_attachment_menu_selection_done() {
        attachment_menu = null;
    }

    private void save_attachment(Geary.Attachment attachment) {
        Gee.List<Geary.Attachment> attachments = new Gee.ArrayList<Geary.Attachment>();
        attachments.add(attachment);
        save_attachments(attachments);
    }
    
    private void on_mark_read_message(Geary.Email message) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_message(message, null, flags);
    }

    private void on_mark_unread_message(Geary.Email message) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_message(message, flags, null);
    }

    private void on_print_message(Geary.Email message) {
        try {
            email_to_element.get(message.id).get_class_list().add("print");
            get_main_frame().print();
            email_to_element.get(message.id).get_class_list().remove("print");
        } catch (GLib.Error error) {
            debug("Hiding elements for printing failed: %s", error.message);
        }
    }
    
    private void flag_message(Geary.Email email) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_message(email, flags, null);
    }

    private void unflag_message(Geary.Email email) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_message(email, null, flags);
    }

    private void show_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
        attachment_menu = build_attachment_menu(email, attachment);
        attachment_menu.show_all();
        attachment_menu.popup(null, null, null, 0, 0);
    }
    
    private Gtk.Menu build_attachment_menu(Geary.Email email, Geary.Attachment attachment) {
        Gtk.Menu menu = new Gtk.Menu();
        menu.selection_done.connect(on_attachment_menu_selection_done);
        
        Gtk.MenuItem save_attachment_item = new Gtk.MenuItem.with_mnemonic(_("_Save As..."));
        save_attachment_item.activate.connect(() => save_attachment(attachment));
        menu.append(save_attachment_item);
        
        if (email.attachments.size > 1) {
            Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(_("Save All A_ttachments..."));
            save_all_item.activate.connect(() => save_attachments(email.attachments));
            menu.append(save_all_item);
        }
        
        return menu;
    }
    
    private void show_message_menu(Geary.Email email) {
        message_menu = build_message_menu(email);
        message_menu.show_all();
        message_menu.popup(null, null, null, 0, 0);
    }
    
    private Gtk.Menu build_message_menu(Geary.Email email) {
        Gtk.Menu menu = new Gtk.Menu();
        menu.selection_done.connect(on_message_menu_selection_done);
        
        if (email.attachments.size > 0) {
            string mnemonic = ngettext("Save A_ttachment...", "Save All A_ttachments...",
                email.attachments.size);
            Gtk.MenuItem save_all_item = new Gtk.MenuItem.with_mnemonic(mnemonic);
            save_all_item.activate.connect(() => save_attachments(email.attachments));
            menu.append(save_all_item);
            menu.append(new Gtk.SeparatorMenuItem());
        }
        
        // Reply to a message.
        Gtk.MenuItem reply_item = new Gtk.MenuItem.with_mnemonic(_("_Reply"));
        reply_item.activate.connect(() => reply_to_message(email));
        menu.append(reply_item);

        // Reply to all on a message.
        Gtk.MenuItem reply_all_item = new Gtk.MenuItem.with_mnemonic(_("Reply to _All"));
        reply_all_item.activate.connect(() => reply_all_message(email));
        menu.append(reply_all_item);

        // Forward a message.
        Gtk.MenuItem forward_item = new Gtk.MenuItem.with_mnemonic(_("_Forward"));
        forward_item.activate.connect(() => forward_message(email));
        menu.append(forward_item);

        // Separator.
        menu.append(new Gtk.SeparatorMenuItem());
        
        // Mark as read/unread.
        if (current_folder is Geary.FolderSupportsMark) {
            if (email.is_unread().to_boolean(false)) {
                Gtk.MenuItem mark_read_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Read"));
                mark_read_item.activate.connect(() => on_mark_read_message(email));
                menu.append(mark_read_item);
            } else {
                Gtk.MenuItem mark_unread_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Unread"));
                mark_unread_item.activate.connect(() => on_mark_unread_message(email));
                menu.append(mark_unread_item);
            }
        }
        
        // Print a message.
        Gtk.MenuItem print_item = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.PRINT, null);
        print_item.activate.connect(() => on_print_message(email));
        menu.append(print_item);

        // Separator.
        menu.append(new Gtk.SeparatorMenuItem());

        // View original message source.
        Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("_View Source"));
        view_source_item.activate.connect(() => on_view_source(email));
        menu.append(view_source_item);

        return menu;
    }

    private WebKit.DOM.HTMLDivElement create_quote_container() throws Error {
        WebKit.DOM.HTMLDivElement quote_container = get_dom_document().create_element("div")
            as WebKit.DOM.HTMLDivElement;
        quote_container.set_attribute("class", "quote_container");
        quote_container.set_inner_html("%s%s%s".printf("<div class=\"shower\">[show]</div>",
            "<div class=\"hider\">[hide]</div>", "<div class=\"quote\"></div>"));
        return quote_container;
    }

    private string[] split_message_and_signature(string text) {
        try {
            Regex signature_regex = new Regex("\\R--\\s*\\R", RegexCompileFlags.MULTILINE);
            return signature_regex.split_full(text, -1, 0, 0, 2);
        } catch (RegexError e) {
            debug("Regex error searching for signature: %s", e.message);
            return new string[0];
        }
    }
    
    private string set_up_quotes(string text) {
        try {
            // Extract any quote containers from the signature block and make them controllable.
            WebKit.DOM.HTMLElement container = get_dom_document().create_element("div")
                as WebKit.DOM.HTMLElement;
            container.set_inner_html(text);
            WebKit.DOM.NodeList quote_list = container.query_selector_all(".signature .quote_container");
            for (int i = 0; i < quote_list.length; ++i) {
                WebKit.DOM.Element quote = quote_list.item(i) as WebKit.DOM.Element;
                quote.set_attribute("class", "quote_container controllable hide");
                container.append_child(quote);
            }
            
            // If there is only one quote container in the message, set it up as controllable.
            quote_list = container.query_selector_all(".quote_container");
            if (quote_list.length == 1) {
                ((WebKit.DOM.Element) quote_list.item(0)).set_attribute("class",
                    "quote_container controllable hide");
            }
            return container.get_inner_html();
        } catch (Error error) {
            debug("Error adjusting final quote block: %s", error.message);
            return text;
        }
    }

    private string insert_plain_text_markup(string text) {
        // Plain text signature and quote:
        // -- 
        // Nate
        //
        // 2012/3/14 Nate Lillich &lt;nate@yorba.org&gt;#015
        // &gt;
        // &gt;
        //
        // Wrap all quotes in hide/show controllers.
        string message = "";
        try {
            WebKit.DOM.HTMLElement container = get_dom_document().create_element("div")
                as WebKit.DOM.HTMLElement;
            int offset = 0;
            while (offset < text.length) {
                // Find the beginning of a quote block.
                int quote_start = text.index_of("&gt;") == 0 && message.length == 0 ? 0 :
                    text.index_of("\n&gt;", offset);
                if (quote_start == -1) {
                    break;
                } else if (text.get(quote_start) == '\n') {
                    // Don't include the newline.
                    ++quote_start;
                }
                
                // Find the end of the quote block.
                int quote_end = quote_start;
                do {
                    quote_end = text.index_of("\n", quote_end + 1);
                } while (quote_end != -1 && quote_end == text.index_of("\n&gt;", quote_end));
                if (quote_end == -1) {
                    quote_end = text.length;
                }

                // Copy the stuff before the quote, then the wrapped quote.
                WebKit.DOM.Element quote_container = create_quote_container();
                Util.DOM.select(quote_container, ".quote").set_inner_html(
                    decorate_quotes(text.substring(quote_start, quote_end - quote_start)));
                container.append_child(quote_container);
                if (quote_start > offset) {
                    message += text.substring(offset, quote_start - offset);
                }
                message += container.get_inner_html();
                offset = quote_end;
                container.set_inner_html("");
            }
            
            // Append everything that's left.
            if (offset != text.length) {
                message += text.substring(offset);
            }
        } catch (Error error) {
            debug("Error wrapping plaintext quotes: %s", error.message);
            return text;
        }

        // Find the signature marker (--) at the beginning of a line.
        string[] message_chunks = split_message_and_signature(message);
        string signature = "";
        if (message_chunks.length == 2) {
            signature = "<div class=\"signature\">%s</div>".printf(
                message.substring(message_chunks[0].length).strip());
            message = "<div>%s</div>".printf(message_chunks[0]);
        }
        return "<pre>" + set_up_quotes(message + signature) + "</pre>";
    }

    private string decorate_quotes(string text) throws Error {
        int level = 0;
        string outtext = "";
        Regex quote_leader = new Regex("^(&gt;)* ?");  // Some &gt; followed by optional space

        foreach (string line in text.split("\n")) {
            MatchInfo match_info;
            if (quote_leader.match_all(line, 0, out match_info)) {
                int start, end, new_level;
                match_info.fetch_pos(0, out start, out end);
                new_level = end / 4;  // Cast to int removes 0.25 from space at end, if present
                while (new_level > level) {
                    outtext += "<blockquote>";
                    level += 1;
                }
                while (new_level < level) {
                    outtext += "</blockquote>";
                    level -= 1;
                }
                outtext += line.substring(end);
            } else {
                debug("This line didn't match the quote regex: %s", line);
                outtext += line;
            }
        }
        // Close any remaining blockquotes.
        while (level > 0) {
            outtext += "</blockquote>";
            level -= 1;
        }
        return outtext;
    }

    private string insert_html_markup(string text, Geary.Email email) {
        try {
            // Create a workspace for manipulating the HTML.
            WebKit.DOM.Document document = get_dom_document();
            WebKit.DOM.HTMLElement container = document.create_element("div") as WebKit.DOM.HTMLElement;
            container.set_inner_html(text);
            
            // Some HTML messages like to wrap themselves in full, proper html, head, and body tags.
            // If we have that here, lets remove it since we are sticking it in our own document.
            WebKit.DOM.HTMLElement? body = Util.DOM.select(container, "body");
            if (body != null) {
                container.set_inner_html(body.get_inner_html());
            }

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

            // Then get all inline images and replace them with data URLs.
            WebKit.DOM.NodeList inline_list = container.query_selector_all("img[src^=\"cid:\"]");
            for (int i = 0; i < inline_list.length; ++i) {
                // Get the MIME content for the image.
                WebKit.DOM.HTMLImageElement img = (WebKit.DOM.HTMLImageElement) inline_list.item(i);
                string mime_id = img.get_attribute("src").substring(4);
                Geary.Memory.AbstractBuffer image_content =
                    email.get_message().get_content_by_mime_id(mime_id);
                uint8[] image_data = image_content.get_array();

                // Get the content type.
                bool uncertain_content_type;
                string mimetype = ContentType.get_mime_type(ContentType.guess(null, image_data,
                    out uncertain_content_type));

                // Then set the source to a data url.
                set_data_url(img, mimetype, image_data);
            }

            // Now return the whole message.
            return set_up_quotes(container.get_inner_html());
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
        WebKit.DOM.Element elem = div_list.item(i) as WebKit.DOM.Element;
        WebKit.DOM.HTMLElement signature_container = get_dom_document().create_element("div")
            as WebKit.DOM.HTMLElement;
        signature_container.set_attribute("class", "signature");
        do {
            // Get its sibling _before_ we move it into the signature div.
            WebKit.DOM.Element? sibling = elem.get_next_element_sibling() as WebKit.DOM.Element;
            if (!elem.get_attribute("class").contains("quote_container")) {
                signature_container.append_child(elem);
            }
            elem = sibling;
        } while (elem != null);
        container.append_child(signature_container);
    }
    
    private bool node_is_child_of(WebKit.DOM.Node node, string ancestor_tag) {
        WebKit.DOM.Element? ancestor = node.get_parent_element();
        for (; ancestor != null; ancestor = ancestor.get_parent_element()) {
            if (ancestor.get_tag_name() == ancestor_tag) {
                return true;
            }
        }
        return false;
    }

    public void remove_message(Geary.Email email) {
        if (!messages.contains(email))
            return;
        
        WebKit.DOM.HTMLElement element = email_to_element.get(email.id);
        email_to_element.unset(email.id);
        
        try {
            if (element.get_parent_element() != null)
                element.get_parent_element().remove_child(element);
        } catch (Error err) {
            debug("Could not remove message: %s", err.message);
        }
    }

    private string create_header_row(string title, string value, bool important) {
        return """
            <div class="field %s">
                <div class="title">%s</div>
                <div class="value">%s</div>
            </div>""".printf(important ? "important" : "", title, value);
    }

    // Appends a header field to header_text
    private void insert_header(ref string header_text, string _title, string? _value,
        bool important = false) {
        if (Geary.String.is_empty(_value))
            return;
        
        string title = Geary.HTML.escape_markup(_title);
        string value = Geary.HTML.escape_markup(_value);
        
        header_text += create_header_row(title, value, important);
    }

    private void insert_header_date(ref string header_text, string _title, DateTime _value,
        bool important = false){

        Date.ClockFormat clock_format = GearyApplication.instance.config.clock_format;
        string title = Geary.HTML.escape_markup(_title);
        string value = """
                <span class="hidden_only">%s</span>
                <span class="not_hidden_only">%s</span>
            """.printf(Date.pretty_print(_value, clock_format),
                Date.pretty_print_verbose(_value, clock_format));
        header_text += create_header_row(title, value, important);
    }

    // Appends email address fields to the header.
    private void insert_header_address(ref string header_text, string title,
        Geary.RFC822.MailboxAddresses? addresses, bool important = false) {
        if (addresses == null)
            return;

        int i = 0;
        string value = "";
        Gee.List<Geary.RFC822.MailboxAddress> list = addresses.get_all();
        foreach (Geary.RFC822.MailboxAddress a in list) {
            value += "<a href='mailto:%s'>".printf(a.address);
            if (a.name != null) {
                value += "<span class='address_name'>%s</span> ".printf(a.name);
                value += "<span class='address_value'>%s</span>".printf(a.address);
            } else {
                value += "<span class='address_name'>%s</span>".printf(a.address);
            }
            value += "</a>";

            if (++i < list.size)
                value += ", ";
        }

        header_text += create_header_row(Geary.HTML.escape_markup(title), value, important);
    }
    
    private string linkify_and_escape_plain_text(string input) throws Error {
        // Convert < and > into non-printable characters, and change & to &amp;.
        string output = input.replace("<", " \01 ").replace(">", " \02 ").replace("&", "&amp;");
        
        // Converts text links into HTML hyperlinks.
        Regex r = new Regex(URL_REGEX, RegexCompileFlags.CASELESS);
        
        output = r.replace_eval(output, -1, 0, 0, is_valid_url);
        return output.replace(" \01 ", "&lt;").replace(" \02 ", "&gt;");
    }

    private void insert_attachments(WebKit.DOM.HTMLElement email_container,
        Gee.List<Geary.Attachment> attachments) {

        // <div class="attachment_container">
        //     <div class="top_border"></div>
        //     <table class="attachment" data-attachment-id="">
        //         <tr>
        //             <td class="preview">
        //                 <img src="" />
        //             </td>
        //             <td class="info">
        //                 <div class="filename"></div>
        //                 <div class="filesize"></div>
        //             </td>
        //         </tr>
        //     </table>
        // </div>

        try {
            // Prepare the dom for our attachments.
            WebKit.DOM.Document document = get_dom_document();
            WebKit.DOM.HTMLElement attachment_container =
                Util.DOM.clone_select(document, "#attachment_template");
            WebKit.DOM.HTMLElement attachment_template =
                Util.DOM.select(attachment_container, ".attachment");
            attachment_container.remove_attribute("id");
            attachment_container.remove_child(attachment_template);

            // Create an attachment table for each attachment.
            foreach (Geary.Attachment attachment in attachments) {
                // Generate the attachment table.
                WebKit.DOM.HTMLElement attachment_table = Util.DOM.clone_node(attachment_template);
                string filename = Geary.String.is_null_or_whitespace(attachment.filename) ?
                    _("none") : attachment.filename;
                Util.DOM.select(attachment_table, ".info .filename")
                    .set_inner_text(filename);
                Util.DOM.select(attachment_table, ".info .filesize")
                    .set_inner_text(Files.get_filesize_as_string(attachment.filesize));
                attachment_table.set_attribute("data-attachment-id", "%lld".printf(attachment.id));

                // Set the image preview and insert it into the container.
                WebKit.DOM.HTMLImageElement img =
                    Util.DOM.select(attachment_table, ".preview img") as WebKit.DOM.HTMLImageElement;
                set_image_src(img, attachment.mime_type, attachment.filepath, ATTACHMENT_PREVIEW_SIZE);
                attachment_container.append_child(attachment_table);
            }

            // Append the attachments to the email.
            email_container.append_child(attachment_container);
        } catch (Error error) {
            debug("Failed to insert attachments: %s", error.message);
        }
    }

    // Validates a URL.
    // Ensures the URL begins with a valid protocol specifier.  (If not, we don't
    // want to linkify it.)
    private bool is_valid_url(MatchInfo match_info, StringBuilder result) {
        try {
            string? url = match_info.fetch(0);
            Regex r = new Regex(PROTOCOL_REGEX, RegexCompileFlags.CASELESS);
            
            result.append(r.match(url) ? "<a href=\"%s\">%s</a>".printf(url, url) : url);
        } catch (Error e) {
            debug("URL parsing error: %s\n", e.message);
        }
        return false; // False to continue processing.
    }
    
    // Scrolls back up to the top.
    public void scroll_reset() {
        get_dom_document().get_default_view().scroll(0, 0);
    }
    
    private bool on_navigation_policy_decision_requested(WebKit.WebFrame frame,
        WebKit.NetworkRequest request, WebKit.WebNavigationAction navigation_action,
        WebKit.WebPolicyDecision policy_decision) {
        policy_decision.ignore();
        
        // Other policy-decisions may be requested for various reasons. The existence of an iframe,
        // for example, causes a policy-decision request with an "OTHER" reason. We don't want to
        // open a webpage in the browser just because an email contains an iframe.
        if (navigation_action.reason == WebKit.WebNavigationReason.LINK_CLICKED)
            link_selected(request.uri);
        return true;
    }
    
    private void on_parent_set(Gtk.Widget? previous_parent) {
        // Since we know the parent will only be set once, there's
        // no need to worry about disconnecting the signal.
        if (get_parent() != null)
            parent.size_allocate.connect(on_size_allocate);
    }
    
    private void on_size_allocate(Gtk.Allocation allocation) {
        // Store the dimensions, then ask for a resize.
        width = allocation.width;
        height = allocation.height;
        
        queue_resize();
    }
    
    private void on_hovering_over_link(string? title, string? url) {
        // Copy the link the user is hovering over.  Note that when the user mouses-out, 
        // this signal is called again with null for both parameters.
        hover_url = url;
        link_hover(hover_url);
    }
    
    private void on_copy_text() {
        copy_clipboard();
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
        if (hover_url.has_prefix(MAILTO_SCHEME))
            clipboard.set_text(hover_url.substring(MAILTO_SCHEME.length, -1), -1);
        else
            clipboard.set_text(hover_url, -1);
        clipboard.store();
    }
    
    private void on_select_all() {
        select_all();
    }
    
    private void on_view_source(Geary.Email message) {
        string source = message.header.buffer.to_string() + message.body.buffer.to_string();
        
        try {
            string temporary_filename;
            int temporary_handle = FileUtils.open_tmp("geary-message-XXXXXX.txt",
                                                      out temporary_filename);
            FileUtils.set_contents(temporary_filename, source);
            FileUtils.close(temporary_handle);
            string temporary_uri = Filename.to_uri(temporary_filename, null);
            Gtk.show_uri(get_screen(), temporary_uri, Gdk.CURRENT_TIME);
        } catch (Error error) {
            var dialog = new Gtk.MessageDialog(null, 0,
                Gtk.MessageType.ERROR, Gtk.ButtonsType.OK,
                _("Failed to open default text editor."));
            dialog.format_secondary_text(error.message);
            dialog.run();
            dialog.destroy();
        }
    }
    
    public override bool query_tooltip(int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
        // Disable tooltips from within WebKit itself.
        return false;
    }
    
    public override void get_preferred_height (out int minimum_height, out int natural_height) {
        minimum_height = height;
        natural_height = height;
    }
    
    public override void get_preferred_width (out int minimum_width, out int natural_width) {
        minimum_width = width;
        natural_width = width;
    }

    public override bool scroll_event(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            if (event.direction == Gdk.ScrollDirection.UP) {
                zoom_in();
                return true;
            } else if (event.direction == Gdk.ScrollDirection.DOWN) {
                zoom_out();
                return true;
            }
        }
        return false;
    }

}

