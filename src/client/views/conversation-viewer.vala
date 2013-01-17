/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class ConversationViewer : Gtk.Box {
    public const Geary.Email.Field REQUIRED_FIELDS =
        Geary.Email.Field.HEADER
        | Geary.Email.Field.BODY
        | Geary.Email.Field.ORIGINATORS
        | Geary.Email.Field.RECEIVERS
        | Geary.Email.Field.SUBJECT
        | Geary.Email.Field.DATE
        | Geary.Email.Field.FLAGS
        | Geary.Email.Field.PREVIEW;
    
    private const int ATTACHMENT_PREVIEW_SIZE = 50;
    private const string MESSAGE_CONTAINER_ID = "message_container";
    private const string SELECTION_COUNTER_ID = "multiple_messages";
    
    // Fired when the user clicks a link.
    public signal void link_selected(string link);
    
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
    
    // The HTML viewer to view the emails.
    public ConversationWebView web_view { get; private set; }
    
    // The Info Bar to be shown when an external image is blocked.
    public Gtk.InfoBar external_images_info_bar { get; private set; }
    
    // Label for displaying overlay messages.
    private Gtk.Label message_overlay_label;
    
    // Maps emails to their corresponding elements.
    private Gee.HashMap<Geary.EmailIdentifier, WebKit.DOM.HTMLElement> email_to_element = new
        Gee.HashMap<Geary.EmailIdentifier, WebKit.DOM.HTMLElement>(Geary.Hashable.hash_func,
        Geary.Equalable.equal_func);
    
    private string? hover_url = null;
    private Gtk.Menu? context_menu = null;
    private Gtk.Menu? message_menu = null;
    private Gtk.Menu? attachment_menu = null;
    private weak Geary.Folder? current_folder = null;
    private Geary.AccountSettings? current_settings = null;
    
    public ConversationViewer() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
        
        external_images_info_bar = new Gtk.InfoBar.with_buttons(
            _("_Show Images"), Gtk.ResponseType.OK, _("_Cancel"), Gtk.ResponseType.CANCEL);
        external_images_info_bar.no_show_all = true;
        external_images_info_bar.response.connect(on_external_images_info_bar_response);
        external_images_info_bar.message_type = Gtk.MessageType.WARNING;
        Gtk.Box? external_images_info_bar_content_area =
            external_images_info_bar.get_content_area() as Gtk.Box;
        if (external_images_info_bar_content_area != null) {
            Gtk.Label label = new Gtk.Label(_("This message contains images. Do you want to show them?"));
            label.set_line_wrap(true);
            external_images_info_bar_content_area.add(label);
            label.show_all();
        }
        pack_start(external_images_info_bar, false, false);
        
        web_view = new ConversationWebView();
        
        web_view.hovering_over_link.connect(on_hovering_over_link);
        web_view.realize.connect( () => { web_view.get_vadjustment().value_changed.connect(mark_read); });
        web_view.size_allocate.connect(mark_read);

        web_view.image_load_requested.connect(on_image_load_requested);
        web_view.link_selected.connect((link) => { link_selected(link); });
        
        Gtk.ScrolledWindow conversation_viewer_scrolled = new Gtk.ScrolledWindow(null, null);
        conversation_viewer_scrolled.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        conversation_viewer_scrolled.add(web_view);
        
        Gtk.Overlay message_overlay = new Gtk.Overlay();
        message_overlay.add(conversation_viewer_scrolled);
        
        message_overlay_label = new Gtk.Label(null);
        message_overlay_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        message_overlay_label.halign = Gtk.Align.START;
        message_overlay_label.valign = Gtk.Align.END;
        message_overlay.add_overlay(message_overlay_label);
        
        pack_start(message_overlay);
    }
    
    private void on_image_load_requested() {
        external_images_info_bar.show();
    }
    
    private void on_external_images_info_bar_response(Gtk.InfoBar sender, int response_id) {
        web_view.apply_load_external_images(response_id == Gtk.ResponseType.OK);
        sender.hide();
    }
    
    public Geary.Email? get_last_message() {
        return messages.is_empty ? null : messages.last();
    }
    
    // Removes all displayed e-mails from the view.
    public void clear(Geary.Folder? new_folder, Geary.AccountSettings? settings) {
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
        current_settings = settings;
    }
    
    // Converts an email ID into HTML ID used by the <div> for the email.
    private string get_div_id(Geary.EmailIdentifier id) {
        return "message_%s".printf(id.to_string());
    }
    
    public void show_multiple_selected(uint selected_count) {
        // Remove any messages and hide the message container, then show the counter.
        clear(current_folder, current_settings);
        try {
            web_view.hide_element_by_id(MESSAGE_CONTAINER_ID);
            web_view.show_element_by_id(SELECTION_COUNTER_ID);
            
            // Update the counter's count.
            WebKit.DOM.HTMLElement counter =
                web_view.get_dom_document().get_element_by_id("selection_counter") as WebKit.DOM.HTMLElement;
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
        web_view.apply_load_external_images(false);
        
        // Make sure the message container is showing and the multi-message counter hidden.
        try {
            web_view.show_element_by_id(MESSAGE_CONTAINER_ID);
            web_view.hide_element_by_id(SELECTION_COUNTER_ID);
        } catch (Error e) {
            debug("Error showing/hiding containers: %s", e.message);
        }

        if (messages.contains(email))
            return;
        
        string message_id = get_div_id(email.id);
        string header = "";
        
        WebKit.DOM.Node insert_before = web_view.container.get_last_child();
        
        messages.add(email);
        Geary.Email? higher = messages.higher(email);
        if (higher != null)
            insert_before = web_view.get_dom_document().get_element_by_id(get_div_id(higher.id));
        
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
            div_message = Util.DOM.clone_select(web_view.get_dom_document(), "#email_template");
            div_message.set_attribute("id", message_id);
            web_view.container.insert_before(div_message, insert_before);
            div_email_container = Util.DOM.select(div_message, "div.email_container");
            if (email.is_unread() == Geary.Trillian.FALSE) {
                div_message.get_class_list().add("hide");
            }
        } catch (Error setup_error) {
            warning("Error setting up webkit: %s", setup_error.message);
            
            return;
        }
        
        email_to_element.set(email.id, div_message);
        
        insert_header_address(ref header, _("From:"), email.from != null ? email.from : email.sender,
            true);
        
        // Only include to string if it's not just this account.
        // TODO: multiple accounts.
        if (email.to != null && current_settings != null) {
            if (!(email.to.get_all().size == 1 && email.to.get_all().get(0).address == current_settings.email.address))
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
                debug("Failed to inject avatar URL: %s", error.message);
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

        // Set attachment icon and add the attachments container if we have any attachments.
        set_attachment_icon(div_message, email.attachments.size > 0);
        if (email.attachments.size > 0) {
            insert_attachments(div_message, email.attachments);
        }

        // Add classes according to the state of the email.
        update_flags(email);

        // Attach to the click events for hiding/showing quotes, opening the menu, and so forth.
        bind_event(web_view, ".email", "contextmenu", (Callback) on_context_menu, this);
        bind_event(web_view, ".quote_container > .hider", "click", (Callback) on_hide_quote_clicked);
        bind_event(web_view, ".quote_container > .shower", "click", (Callback) on_show_quote_clicked);
        bind_event(web_view, ".email_container .menu", "click", (Callback) on_menu_clicked, this);
        bind_event(web_view, ".email_container .starred", "click", (Callback) on_unstar_clicked, this);
        bind_event(web_view, ".email_container .unstarred", "click", (Callback) on_star_clicked, this);
        bind_event(web_view, ".header .field .value", "click", (Callback) on_value_clicked, this);
        bind_event(web_view, ".email .header_container", "click", (Callback) on_body_toggle_clicked, this);
        bind_event(web_view, ".attachment_container .attachment", "click", (Callback) on_attachment_clicked, this);
        bind_event(web_view, ".attachment_container .attachment", "contextmenu", (Callback) on_attachment_menu, this);
    }
    
    public void unhide_last_email() {
        WebKit.DOM.HTMLElement last_email = (WebKit.DOM.HTMLElement) web_view.container.get_last_child().previous_sibling;
        if (last_email != null) {
            WebKit.DOM.DOMTokenList class_list = last_email.get_class_list();
            try {
                class_list.remove("hide");
            } catch (Error error) {
                // Expected, if not hidden
            }
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

    private void set_attachment_icon(WebKit.DOM.HTMLElement container, bool show) {
        try {
            WebKit.DOM.DOMTokenList class_list = container.get_class_list();
            Util.DOM.toggle_class(class_list, "attachment", show);
        } catch (Error e) {
            warning("Failed to set attachment icon: %s", e.message);
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
        } catch (Error e) {
            warning("Failed to set classes on .email: %s", e.message);
        }
    }

    private static void on_context_menu(WebKit.DOM.Element clicked_element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        Geary.Email email = conversation_viewer.get_email_from_element(clicked_element);
        if (email != null)
            conversation_viewer.show_context_menu(email);
    }
    
    private void show_context_menu(Geary.Email email) {
        context_menu = build_context_menu(email);
        context_menu.show_all();
        context_menu.popup(null, null, null, 0, 0);
    }
    
    private Gtk.Menu build_context_menu(Geary.Email email) {
        Gtk.Menu menu = new Gtk.Menu();
        
        if (web_view.can_copy_clipboard()) {
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
                menu.append(item);
            }
        }
        
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
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email email = conversation_viewer.get_email_from_element(element);
        if (email != null)
            conversation_viewer.show_message_menu(email);
    }

    private static void on_unstar_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        if (email != null)
            conversation_viewer.unflag_message(email);
    }

    private static void on_star_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        if (email != null)
            conversation_viewer.flag_message(email);
    }

    private static void on_value_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        if (!conversation_viewer.is_hidden_email(element))
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
        ConversationViewer conversation_viewer) {
        conversation_viewer.on_body_toggle_clicked_self(element);
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

        mark_read();
    }

    private static void on_attachment_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        ConversationViewer conversation_viewer) {
        conversation_viewer.on_attachment_clicked_self(element);
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
        ConversationViewer conversation_viewer) {
        event.stop_propagation();
        Geary.Email? email = conversation_viewer.get_email_from_element(element);
        Geary.Attachment? attachment = conversation_viewer.get_attachment_from_element(element);
        if (email != null && attachment != null)
            conversation_viewer.show_attachment_menu(email, attachment);
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
        mark_manual_read(message.id);
    }

    private void on_mark_unread_message(Geary.Email message) {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_message(message, flags, null);
        mark_manual_read(message.id);
    }

    // Use this when an email has been marked read through manual (user) intervention
    public void mark_manual_read(Geary.EmailIdentifier id) {
        if (email_to_element.has_key(id)) {
            try {
                email_to_element.get(id).get_class_list().add("manual_read");
            } catch (Error error) {
                debug("Adding manual_read class failed: %s", error.message);
            }
        }
    }

    private void on_print_message(Geary.Email message) {
        try {
            email_to_element.get(message.id).get_class_list().add("print");
            web_view.get_main_frame().print();
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
        WebKit.DOM.HTMLDivElement quote_container = web_view.create_div();
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
            WebKit.DOM.HTMLElement container = web_view.create_div();
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
            WebKit.DOM.HTMLElement container = web_view.create_div();
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
    
    private string insert_html_markup(string text, Geary.Email email) {
        try {
            // Create a workspace for manipulating the HTML.
            WebKit.DOM.HTMLElement container = web_view.create_div();
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

            // Then look for all <img> tags. Inline images are replaced with
            // data URLs, while external images are added to
            // external_images_uri (to be used later by is_image()).
            Gee.ArrayList<string> external_images_uri = new Gee.ArrayList<string>();
            WebKit.DOM.NodeList inline_list = container.query_selector_all("img");
            for (ulong i = 0; i < inline_list.length; ++i) {
                // Get the MIME content for the image.
                WebKit.DOM.HTMLImageElement img = (WebKit.DOM.HTMLImageElement) inline_list.item(i);
                string? src = img.get_attribute("src");
                if (Geary.String.is_empty(src)) {
                    continue;
                } else if (src.has_prefix("cid:")) {
                    string mime_id = src.substring(4);
                    Geary.Memory.AbstractBuffer image_content =
                        email.get_message().get_content_by_mime_id(mime_id);
                    uint8[] image_data = image_content.get_array();

                    // Get the content type.
                    bool uncertain_content_type;
                    string mimetype = ContentType.get_mime_type(ContentType.guess(null, image_data,
                        out uncertain_content_type));

                    // Then set the source to a data url.
                    web_view.set_data_url(img, mimetype, image_data);
                } else if (!src.has_prefix("data:")) {
                    external_images_uri.add(src);
                    if (!web_view.load_external_images)
                        external_images_info_bar.show();
                }
            }

            web_view.set_external_images_uris(external_images_uri);

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
        WebKit.DOM.HTMLElement signature_container = web_view.create_div();
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
        
        header_text += create_header_row(Geary.HTML.escape_markup(_title),
            Geary.HTML.escape_markup(_value), important);
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
            WebKit.DOM.Document document = web_view.get_dom_document();
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
                string filename = Geary.String.is_empty_or_whitespace(attachment.filename) ?
                    _("none") : attachment.filename;
                Util.DOM.select(attachment_table, ".info .filename")
                    .set_inner_text(filename);
                Util.DOM.select(attachment_table, ".info .filesize")
                    .set_inner_text(Files.get_filesize_as_string(attachment.filesize));
                attachment_table.set_attribute("data-attachment-id", "%s".printf(attachment.id.to_string()));

                // Set the image preview and insert it into the container.
                WebKit.DOM.HTMLImageElement img =
                    Util.DOM.select(attachment_table, ".preview img") as WebKit.DOM.HTMLImageElement;
                web_view.set_image_src(img, attachment.mime_type, attachment.filepath, ATTACHMENT_PREVIEW_SIZE);
                attachment_container.append_child(attachment_table);
            }

            // Append the attachments to the email.
            email_container.append_child(attachment_container);
        } catch (Error error) {
            debug("Failed to insert attachments: %s", error.message);
        }
    }
    
    public void scroll_reset() {
        web_view.scroll_reset();
    }
    
    private void on_hovering_over_link(string? title, string? url) {
        // Copy the link the user is hovering over.  Note that when the user mouses-out, 
        // this signal is called again with null for both parameters.
        hover_url = url;
        message_overlay_label.label = hover_url;
    }
    
    private void on_copy_text() {
        web_view.copy_clipboard();
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
        if (hover_url.has_prefix(Geary.ComposedEmail.MAILTO_SCHEME))
            clipboard.set_text(hover_url.substring(Geary.ComposedEmail.MAILTO_SCHEME.length, -1), -1);
        else
            clipboard.set_text(hover_url, -1);
        clipboard.store();
    }
    
    private void on_select_all() {
        web_view.select_all();
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
            Gtk.show_uri(web_view.get_screen(), temporary_uri, Gdk.CURRENT_TIME);
        } catch (Error error) {
            ErrorDialog dialog = new ErrorDialog(GearyApplication.instance.get_main_window(),
                _("Failed to open default text editor."), error.message);
            dialog.run();
        }
    }

    public void mark_read() {
        Gee.List<Geary.EmailIdentifier> ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        WebKit.DOM.Document document = web_view.get_dom_document();
        long scroll_top = document.body.scroll_top;
        long scroll_height = document.document_element.scroll_height;

        foreach (Geary.Email message in messages) {
            try {
                if (message.email_flags.is_unread()) {
                    WebKit.DOM.HTMLElement element = email_to_element.get(message.id);
                    WebKit.DOM.HTMLElement body = (WebKit.DOM.HTMLElement) element.get_elements_by_class_name("body").item(0);
                    if (!element.get_class_list().contains("manual_read") &&
                            body.offset_top + body.offset_height > scroll_top &&
                            body.offset_top + 28 < scroll_top + scroll_height) {  // 28 = 15 padding + 13 first line of text
                        ids.add(message.id);
                    }
                }
            } catch (Error error) {
                debug("Problem checking email class: %s", error.message);
            }
        }

        Geary.FolderSupportsMark? supports_mark = current_folder as Geary.FolderSupportsMark;
        if (supports_mark != null & ids.size > 0) {
            Geary.EmailFlags flags = new Geary.EmailFlags();
            flags.add(Geary.EmailFlags.UNREAD);
            supports_mark.mark_email_async.begin(ids, null, flags, null);
        }
    }
}

