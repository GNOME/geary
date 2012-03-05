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
        | Geary.Email.Field.PROPERTIES;
    
    private const string MESSAGE_CONTAINER_ID = "message_container";
    private const string SELECTION_COUNTER_ID = "multiple_messages";
    private const string HTML_BODY = """
        <html><head><title>Geary</title>
        <style>
        body {
            margin: 0 !important;
            padding: 0 !important;
            background-color: #ccc !important;
            font-size: 10pt !important;
        }
        td, th {
            vertical-align: top;
        }
        .email {
            padding: 15px;
            margin: 15px;
            border: 1px #999 solid;
            background-color: white;
            color: black;
            font-size: small;
            border-radius: 4px;
            -webkit-box-shadow: 0 3px 5px #aaa;
            display: inline-block;
        }
        .email_box {
            box-sizing: border-box;
            -webkit-box-sizing: border-box;
            width: 100% !important;
        }
        .geary_spacer {
            display: table;
            box-sizing: border-box;
            -webkit-box-sizing: border-box;
            width: 100% !important;
        }
        .header_title {
            font-size: 9pt;
            color: #777;
            text-align: right;
            padding-right: 7px;
        }
        .header_text {
            font-size: 9pt;
            color: black;
        }
        .header_address_name {
            color: black;
            font-size: inherit;
        }
        .header_address_value {
            color: #777;
            font-size: inherit;
        }
        hr {
            background-color: #999;
            height: 1px;
            border: 0;
            margin-top: 15px;
            margin-bottom: 15px;
        }
        pre {
            font-family: sans-serif;
            white-space: pre-wrap;
        }
        #multiple_messages {
            display: none;
        }
        #multiple_messages > .email {
            margin: 100px auto;
            display: block;
            text-align: center;
            width: 200px;
        }
        </style>
        </head><body>
        <div id="message_container"><div id="placeholder"></div></div>
        <div id="multiple_messages"><div id="selection_counter" class="email"></div></div>
        </body></html>""";
    
    // Fired when the user clicks a link.
    public signal void link_selected(string link);
    
    // Fired when the user hovers over or stops hovering over a link.
    public signal void link_hover(string? link);
    
    // List of emails in this view.
    public Gee.TreeSet<Geary.Email> messages { get; private set; default = 
        new Gee.TreeSet<Geary.Email>((CompareFunc<Geary.Email>) compare_email); }
    
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
    
    public MessageViewer() {
        valign = Gtk.Align.START;
        vexpand = true;
        set_border_width(0);
        
        navigation_requested.connect(on_navigation_requested);
        parent_set.connect(on_parent_set);
        hovering_over_link.connect(on_hovering_over_link);
        button_press_event.connect(on_button_press_event);
        
        WebKit.WebSettings s = new WebKit.WebSettings();
        s.auto_load_images = false;
        s.enable_default_context_menu = false;
        s.enable_scripts = false;
        s.enable_java_applet = false;
        s.enable_plugins = false;
        settings = s;
        
        // Load the HTML into WebKit.
        load_finished.connect(on_load_finished);
        load_string(HTML_BODY, "text/html", "UTF8", "");
    }
    
    private void on_load_finished(WebKit.WebFrame frame) {
        // Grab the HTML container.
        WebKit.DOM.Element? _container = get_dom_document().get_element_by_id("message_container");
        assert(_container != null);
        container = _container as WebKit.DOM.HTMLDivElement;
        assert(container != null);
    }
    
    // Removes all displayed e-mails from the view.
    public void clear() {
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
        clear();
        try {
            hide_element_by_id(MESSAGE_CONTAINER_ID);
            show_element_by_id(SELECTION_COUNTER_ID);
            
            // Update the counter's count.
            WebKit.DOM.HTMLElement counter =
                get_dom_document().get_element_by_id("selection_counter") as WebKit.DOM.HTMLElement;
            counter.set_inner_html(_("%u conversations selected.").printf(selected_count));
        } catch (Error e) {
            debug("Error updating counterL %s", e.message);
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
            //     <div class="geary spacer"></div>
            //     <div class="email_container">
            //         $EMAIL_BODY
            //     </div>
            // </div>
            div_message = get_dom_document().create_element("div") as WebKit.DOM.HTMLElement;
            div_message.set_attribute("id", message_id);
            div_message.set_attribute("class", "email");
            container.insert_before(div_message, insert_before);
            
            WebKit.DOM.Element spacer = get_dom_document().create_element("div") as
                WebKit.DOM.HTMLElement;
            spacer.set_attribute("class", "geary_spacer");
            div_message.append_child(spacer);
            
            div_email_container = get_dom_document().create_element("div") as WebKit.DOM.HTMLElement;
            div_email_container.set_attribute("class", "email_container");
            div_message.append_child(div_email_container);
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
        
        insert_header_address(ref header, _("From:"), email.from != null ? email.from : 
            email.sender, true);
        
        // Only include to string if it's not just this account.
        // TODO: multiple accounts.
        if (email.to != null) {
            if (!(email.to.get_all().size == 1 && email.to.get_all().get(0).address == username))
                 insert_header_address(ref header, _("To:"), email.to);
        }
        
        insert_header_address(ref header, _("Cc:"), email.cc);
            
        if (email.subject != null)
            insert_header(ref header, _("Subject:"), email.subject.value);
            
        if (email.date != null)
            insert_header(ref header, _("Date:"), Date.pretty_print_verbose(
                email.date.value));
        
        string body_text = "";
        try {
            body_text = email.get_message().get_first_mime_part_of_content_type("text/html").to_utf8();
        } catch (Error err) {
            try {
                body_text = "<pre>" + linkify_and_escape_plain_text(email.get_message().
                    get_first_mime_part_of_content_type("text/plain").to_utf8()) + "</pre>";
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }
        
        body_text = "<hr noshade>" + body_text;
        
        // Graft header and email body into the email container.
        try {
            WebKit.DOM.HTMLElement table_header = get_dom_document().create_element("table")
                as WebKit.DOM.HTMLElement;
            table_header.set_inner_html(header);
            div_email_container.append_child(table_header);
            
            WebKit.DOM.HTMLElement span_body = get_dom_document().create_element("span")
                as WebKit.DOM.HTMLElement;
            span_body.set_inner_html(body_text);
            div_email_container.append_child(span_body);
        } catch (Error html_error) {
            warning("Error setting HTML for message: %s", html_error.message);
        }
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
    
    // Appends a header field to header_text
    private void insert_header(ref string header_text, string _title, string? _value,
        bool escape_value = true) {
        if (Geary.String.is_empty(_value))
            return;
        
        string title = Geary.HTML.escape_markup(_title);
        string value = escape_value ? Geary.HTML.escape_markup(_value) : _value;
        
        header_text += "<tr><td class='header_title'>%s</td><td class='header_text'>%s</td></tr>"
            .printf(title, value);
    }
    
    // Appends email address fields to the header.
    private void insert_header_address(ref string header_text, string title,
        Geary.RFC822.MailboxAddresses? addresses, bool bold = false) {
        if (addresses == null)
            return;
        
        string bold_val = bold ? " style='font-weight: bold'" : "";
        
        string value = "";
        Gee.List<Geary.RFC822.MailboxAddress> list = addresses.get_all();
        int i = 0;
        foreach (Geary.RFC822.MailboxAddress a in list) {
            if (a.name != null) {
                value += "<span class='header_address_name'%s>%s</span> ".printf(bold_val, a.name);
                value += "<span class='header_address_value'>%s</span>".printf(a.address);
            } else {
                value += "<span class='header_address_name'%s>%s</span>".printf(bold_val, a.address);
            }
            
            i++;
            if (i < list.size)
                value += ", ";
        }
        
        insert_header(ref header_text, title, value, false);
    }
    
    private string linkify_and_escape_plain_text(string input) throws Error {
        // Convert < and > into non-printable characters.
        string output = input.replace("<", " \01 ").replace(">", " \02 ");
        
        // Converts text links into HTML hyperlinks.
        // Regex is from here: http://daringfireball.net/2010/07/improved_regex_for_matching_urls
        Regex r = new Regex(
            "(?i)\\b((?:[a-z][\\w-]+:(?:/{1,3}|[a-z0-9%])|www\\d{0,3}[.]|[a-z0-9.\\-]+[.][a-z]{2,4}/)(?:[^\\s()<>]+|\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\))+(?:\\(([^\\s()<>]+|(\\([^\\s()<>]+\\)))*\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’]))",
            RegexCompileFlags.CASELESS);
        
        output = r.replace(output, -1, 0, "<a href=\"\\g<1>\">\\g<1></a>");
        
        return output.replace(" \01 ", "&lt;").replace(" \02 ", "&gt;");
    }
    
    // Scrolls to the first unread message in the view, if any exist.
    public void scroll_to_first_unread() {
        foreach (Geary.Email email in messages) {
            if (email.properties.email_flags.is_unread()) {
                WebKit.DOM.HTMLElement? element = email_to_element.get(email.id);
                if (element != null)
                    element.scroll_into_view(true);
                
                break;
            }
        }
    }
    
    private WebKit.NavigationResponse on_navigation_requested(WebKit.WebFrame frame, 
        WebKit.NetworkRequest request) {
        link_selected(request.uri);
        return WebKit.NavigationResponse.IGNORE;
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
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        c.set_text(hover_url, -1);
        c.store();
    }
    
    private void on_select_all() {
        select_all();
    }
    
    private bool on_button_press_event(Gdk.EventButton event) {
        // Ignore right-clicks on images.
        if (event.button == 3) {
            create_context_menu(event);
            
            return true;
        }
        
        return false;
    }
    
    private void create_context_menu(Gdk.EventButton event) {
        context_menu = new Gtk.Menu();
        
        if (can_copy_clipboard()) {
            // Add a menu item for copying the current selection.
            Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("_Copy"));
            item.activate.connect(on_copy_text);
            context_menu.append(item);
        }
        
        if (hover_url != null) {
            // Add a menu item for copying the link.
            Gtk.MenuItem item = new Gtk.MenuItem.with_mnemonic(_("Copy _Link"));
            item.activate.connect(on_copy_link);
            context_menu.append(item);
        }
        
        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(_("Select _All"));
        select_all_item.activate.connect(on_select_all);
        context_menu.append(select_all_item);
        
        context_menu.show_all();
        context_menu.popup(null, null, null, event.button, event.time);
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
}

