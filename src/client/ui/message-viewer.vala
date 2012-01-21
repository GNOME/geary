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
    
    private const string HTML_BODY = """
        <html><head><title>Geary</title>
        <style>
        body {
            margin: 0;
            padding: 0;
            background-color: #ccc;
        }
        .email {
            padding: 15px;
            margin: 15px;
            border: 1px #999 solid;
            background-color: white;
            color: black;
            font-size: small;
        }
        .header_title {
            font-size: smaller;
            color: #aaaaaa;
        }
        .header_normal {
            font-size: smaller;
            color: black;
        }
        .header_bold {
            font-size: smaller;
            color: black;
            font-weight: bold;
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
        </style>
        </head><body>
        <div id="message_container"><div id="placeholder"></div></div>
        </body></html>""";
    
    // Fired when the user clicks a link.
    public signal void link_selected(string link);
    
    // List of emails corresponding with VBox.
    public Gee.LinkedList<Geary.Email> messages { get; private set; default = 
        new Gee.LinkedList<Geary.Email>(); }
    
    private int width = 0;
    private int height = 0;
    
    public MessageViewer() {
        valign = Gtk.Align.START;
        vexpand = true;
        set_border_width(0);
        
        navigation_requested.connect(on_navigation_requested);
        parent_set.connect(on_parent_set);
        
        WebKit.WebSettings s = new WebKit.WebSettings();
        s.auto_load_images = false;
        s.enable_default_context_menu = false;
        s.enable_scripts = false;
        s.enable_java_applet = false;
        s.enable_plugins = false;
        settings = s;
        
        clear(); // loads HTML page
    }
    
    // Removes all displayed e-mails from the view.
    public void clear() {
        messages.clear();
        load_string(HTML_BODY, "text/html", "UTF8", "");
    }
    
    // Adds a message to the view.
    public void add_message(Geary.Email email) {
        messages.add(email);
        debug("Message id: %s", email.id.to_string());
        
        string message_id = "message_%s".printf(email.id.to_string());
        string header = "<table>";
        
        WebKit.DOMHTMLDivElement? container = null;
        WebKit.DOMHTMLElement? div_message = null;
        
        try {
            WebKit.DOMElement? _container = get_dom_document().get_element_by_id("message_container");
            assert(_container != null);
            container = _container as WebKit.DOMHTMLDivElement;
            assert(container != null);
            
            WebKit.DOMElement? _div_message = get_dom_document().create_element("div");
            assert(_div_message != null);
            div_message = _div_message as WebKit.DOMHTMLElement;
            assert(div_message != null);
            div_message.set_attribute("id", message_id);
            div_message.set_attribute("class", "email");
            container.insert_before(div_message, container.get_last_child());
        } catch (Error setup_error) {
            warning("Error setting up webkit: %s", setup_error.message);
        }
        
        string username;
        try {
            // TODO: Multiple accounts.
            username = Geary.Engine.get_usernames(GearyApplication.instance.
                get_user_data_directory()).get(0);
        } catch (Error e) {
            error("Unable to get username. Error: %s", e.message);
        }
        
        // Only include to string if it's not just this account.
        // TODO: multiple accounts.
        string to = "";
        if (email.to != null) {
            if (!(email.to.get_all().size == 1 && email.to.get_all().get(0).address == username))
                to = email.to.to_string();
        }
        
        if (email.from != null)
            insert_header(ref header, _("From:"), email.from.to_string(), true);
        
        insert_header(ref header, _("To:"), to);
        
        if (email.cc != null)
            insert_header(ref header, _("Cc:"), email.cc.to_string());
            
        if (email.subject != null)
            insert_header(ref header, _("Subject:"), email.subject.value);
            
        if (email.date != null)
            insert_header(ref header, _("Date:"), Date.pretty_print_verbose(
                email.date.value));
        
        header += "</table><hr noshade>";
        
        string body_text = "";
        try {
            body_text = email.get_message().get_first_mime_part_of_content_type("text/html").to_utf8();
        } catch (Error err) {
            try {
                body_text = "<pre>" + email.get_message().get_first_mime_part_of_content_type(
                    "text/plain").to_utf8() + "</pre>";
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }
        
        try {
            div_message.set_inner_html(header + body_text);
        } catch (Error html_error) {
            warning("Error setting HTML for message: %s", html_error.message);
        }
    }
    
    // Appends a header field (to, from, subject, etc.) to header_text
    private void insert_header(ref string header_text, string _title, string? _value,
        bool bold = false) {
        if (Geary.String.is_empty(_value))
            return;
        
        string title = Geary.String.escape_markup(_title);
        string value = Geary.String.escape_markup(_value);
        
        header_text += "<tr><td class='header_title'>%s</td><td class='%s'>%s</td></tr>"
            .printf(title, bold ? "header_bold" : "header_normal", value);
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
    
    public override void get_preferred_height (out int minimum_height, out int natural_height) {
        minimum_height = height;
        natural_height = height;
    }
    
    public override void get_preferred_width (out int minimum_width, out int natural_width) {
        minimum_width = width;
        natural_width = width;
    }
}

