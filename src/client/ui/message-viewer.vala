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
        img {
            display: none;
        }
        img[src^="data:"] {
            display: inline;
        }

        .button {
            border: 1px #fff solid;
            border-radius: 4px;
            cursor: pointer;
            padding: 4px;
            -webkit-user-select: none;
            -webkit-user-drag: none;
            text-align: center;
        }
        .button * {
            -webkit-user-select: none;
            -webkit-user-drag: none;
        }
        .button:hover {
            border-color: #ccc;
            background-color: #ddd;
            box-shadow: inset 2px 2px 7px #f8f8f8;
        }
        .button:active {
            border-color: #aaa;
            background-color: #ddd;
            padding: 5px 3px 3px 5px;
            box-shadow: inset 2px 2px 7px #ccc;
        }

        .email {
            padding: 15px;
            border: 1px #999 solid;
            background-color: white;
            color: black;
            font-size: small;
            border-radius: 4px;
            box-shadow: 0 3px 5px #aaa;
            display: inline-block;
            word-wrap: break-word;
            width: 100%;
            box-sizing:border-box;
            margin: 0 0 15px 0px;
        }
        .email .starred {
            display: none;
        }
        .email .unstarred {
            display: block;
        }
        .email.starred .starred {
            display: block;
        }
        .email.starred .unstarred {
            display: none;
        }
        .email_box {
            box-sizing: border-box;
            -webkit-box-sizing: border-box;
            width: 100% !important;
        }
        .email_container {
            overflow: hidden;
        }
        .email_container > .button_bar {
            float: right;
        }
        .email_container > .button_bar > .button {
            float: left;
        }
        .email_container > .button_bar > .button > .icon {
            width: 16px;
            height: 16px;
        }
        .email_container > hr {
            clear: both;
        }
        .avatar {
            display: none;
        }
        .avatar[src^=file], .avatar[src^=http] {
            display: inline;
            width: 48px; height: 48px;
            float: right;
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

        .signature {
            color: #777;
            display: inline;
        }
        .signature a {
            color: #66f;
        }

        .quote_container {
            margin: 5px 0;
            padding: 5px;
            background-color: #f4f4f4;
            border-radius: 4px;
            box-shadow: inset 0 2px 8px 1px #ccc;
        }
        .quote_container > .shower,
        .quote_container > .hider {
            color: #777;
            font-size: 75%;
            cursor: pointer;
            display: none;
        }
        .quote_container.controllable > .shower {
            display: block;
        }
        .quote_container.controllable > .hider,
        .quote_container.controllable > .quote {
            display: none;
        }
        .quote_container.controllable.show > .shower {
            display: none;
        }
        .quote_container.controllable.show > .hider,
        .quote_container.controllable.show > .quote {
            display: block;
        }
        .quote_container > .shower:hover,
        .quote_container > .hider:hover {
            color: black;
        }

        #message_container {
            position: absolute;
            left: 0;
            right: 0;
            padding: 15px;
        }
        #multiple_messages {
            display: none;
            text-align: center;
        }
        #multiple_messages > .email {
            margin: 100px auto;
            display: inline-block;
            width: auto;
        }
        #email_template {
            display: none;
        }
        </style>
        </head><body>
        <div id="message_container"><div id="placeholder"></div></div>
        <div id="multiple_messages"><div id="selection_counter" class="email"></div></div>
        <div id="email_template" class="email">
            <div class="geary_spacer"></div>
            <div class="email_container">
                <img src="" class="avatar" />
                <div class="button_bar">
                    <div class="starred button"><img src="" class="icon" /></div>
                    <div class="unstarred button"><img src="" class="icon" /></div>
                    <div class="menu button"><img src="" class="icon" /></div>
                </div>
                <table class="header"><tbody></tbody></table>
                <span class="body"></span>
            </div>
        </div>
        </body></html>""";
    
    // Fired when the user clicks a link.
    public signal void link_selected(string link);
    
    // Fired when the user hovers over or stops hovering over a link.
    public signal void link_hover(string? link);

    // Fired when the user clicks "reply" in the message menu.
    public signal void reply_to_message();

    // Fired when the user clicks "reply all" in the message menu.
    public signal void reply_all_message();

    // Fired when the user clicks "forward" in the message menu.
    public signal void forward_message();

    // Fired when the user marks a message.
    public signal void mark_message(Geary.EmailFlags? flags_to_add, Geary.EmailFlags? flags_to_remove);

    // List of emails in this view.
    public Gee.TreeSet<Geary.Email> messages { get; private set; default = 
        new Gee.TreeSet<Geary.Email>((CompareFunc<Geary.Email>) Geary.Email.compare_date_ascending); }
    public Geary.Email? active_email = null;
    
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
        load_string(HTML_BODY, "text/html", "utf8", "");
    }
    
    private void on_load_finished(WebKit.WebFrame frame) {
        // Grab the HTML container.
        WebKit.DOM.Element? _container = get_dom_document().get_element_by_id("message_container");
        assert(_container != null);
        container = _container as WebKit.DOM.HTMLDivElement;
        assert(container != null);

        // Load the icons.
        set_icon_src("#email_template .menu .icon", "down");
        set_icon_src("#email_template .starred .icon", "starred");
        set_icon_src("#email_template .unstarred .icon", "non-starred-grey");

    }

    private void on_resource_request_starting(WebKit.WebFrame web_frame,
        WebKit.WebResource web_resource, WebKit.NetworkRequest request,
        WebKit.NetworkResponse? response) {

        if (!request.get_uri().has_prefix("http://www.gravatar.com/avatar/")
         && !request.get_uri().has_prefix("data:")) {
            request.set_uri("about:blank");
        }
    }

    private void set_icon_src(string selector, string icon_name) {
        try {
            // Load the icon.
            string icon_filename = IconFactory.instance.lookup_icon(icon_name, 16, 0).get_filename();
            uint8[] icon_content;
            FileUtils.get_data(icon_filename, out icon_content);

            // Fetch its mime type.
            bool uncertain_content_type;
            string icon_mimetype = ContentType.get_mime_type(ContentType.guess(icon_filename,
                icon_content, out uncertain_content_type));

            // Then set the source to a data url.
            WebKit.DOM.HTMLImageElement icon = get_dom_document().query_selector(selector)
                as WebKit.DOM.HTMLImageElement;
            icon.set_attribute("src", "data:%s;base64,%s".printf(icon_mimetype,
                Base64.encode(icon_content)));
        } catch (Error error) {
            warning("Failed to load icon '%s': %s", icon_name, error.message);
        }
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
            div_message = get_dom_document().get_element_by_id("email_template").clone_node(true)
                as WebKit.DOM.HTMLElement;
            div_message.set_attribute("id", message_id);
            container.insert_before(div_message, insert_before);
            div_email_container = div_message.query_selector("div.email_container")
                as WebKit.DOM.HTMLElement;
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
                email.date.value, GearyApplication.instance.config.clock_format));
        
        try {
            WebKit.DOM.HTMLImageElement icon = get_dom_document().query_selector("#%s .avatar".printf(message_id))
                as WebKit.DOM.HTMLImageElement;
            string checksum = GLib.Checksum.compute_for_string (
                GLib.ChecksumType.MD5, email.sender.get(0).address);
            string gravatar = "http://www.gravatar.com/avatar/%s?d=mm".printf (checksum);
            icon.set_attribute("src", gravatar);
        } catch (Error error) {
            warning("Failed to load avatar: %s\n", error.message);
        }

        string body_text = "";
        try {
            body_text = email.get_message().get_first_mime_part_of_content_type("text/html").to_utf8();
            body_text = insert_html_markup(body_text);
        } catch (Error err) {
            try {
                body_text = linkify_and_escape_plain_text(email.get_message().
                    get_first_mime_part_of_content_type("text/plain").to_utf8());
                body_text = insert_plain_text_markup(body_text);
            } catch (Error err2) {
                debug("Could not get message text. %s", err2.message);
            }
        }
        body_text = "<hr noshade>" + body_text;
        
        // Graft header and email body into the email container.
        try {
            WebKit.DOM.HTMLElement table_header = div_email_container
                .query_selector("table.header > tbody") as WebKit.DOM.HTMLElement;
            table_header.set_inner_html(header);
            
            WebKit.DOM.HTMLElement span_body = div_email_container.query_selector("span.body")
                as WebKit.DOM.HTMLElement;
            span_body.set_inner_html(body_text);
        } catch (Error html_error) {
            warning("Error setting HTML for message: %s", html_error.message);
        }

        // Add classes according to the state of the email.
        update_flags(email);

        // Attach to the click events for hiding/showing quotes, opening the menu, and so forth.
        bind_event(".email", "contextmenu", (Callback) on_context_menu, this);
        bind_event(".quote_container > .hider", "click", (Callback) on_hide_quote_clicked);
        bind_event(".quote_container > .shower", "click", (Callback) on_show_quote_clicked);
        bind_event(".email_container .menu", "click", (Callback) on_menu_clicked, this);
        bind_event(".email_container .starred", "click", (Callback) on_unstar_clicked, this);
        bind_event(".email_container .unstarred", "click", (Callback) on_star_clicked, this);
    }

    private void bind_event(string selector, string event, Callback callback, Object? extra = null) {
        try {
            WebKit.DOM.NodeList node_list = get_dom_document().query_selector_all(selector);
            for (int i = 0; i < node_list.length; ++i) {
                WebKit.DOM.EventTarget node = node_list.item(i) as WebKit.DOM.EventTarget;
                node.remove_event_listener(event, callback, false);
                node.add_event_listener(event, callback, false, extra);
            }
        } catch (Error error) {
            warning("Error setting up click handlers: %s", error.message);
        }
    }
    
    private WebKit.DOM.Element? closest_ancestor(WebKit.DOM.Element element, string selector) {
        try {
            WebKit.DOM.Element? parent = element.get_parent_element();
            while (parent != null && !parent.webkit_matches_selector(selector)) {
                parent = parent.get_parent_element();
            }
            return parent;
        } catch (Error error) {
            warning("Failed to find ancestor: %s", error.message);
            return null;
        }
    }

    private Geary.Email? get_email_from_element(WebKit.DOM.Element element) {
        // First get the email container.
        WebKit.DOM.Element email_element;
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

        // Next find the ID in the email-to-element map.
        Geary.EmailIdentifier? email_id = null;
        foreach (var entry in email_to_element.entries) {
            if (entry.value == email_element) {
                email_id = entry.key;
                break;
            }
        }

        // Now lookup the email in our messages set.
        foreach (Geary.Email message in messages) {
            if (message.id == email_id) {
                return message;
            }
        }
        return null;
    }

    public void update_flags(Geary.Email email) {
        // Nothing to do if we aren't displaying this email.
        if (!email_to_element.has_key(email.id)) {
            return;
        }

        Geary.EmailFlags flags = email.properties.email_flags;
        
        // Update the flags in out message set.
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
            if (flags.is_unread()) {
                class_list.remove("read");
            } else {
                class_list.add("read");
            }
            if (flags.is_flagged()) {
                class_list.add("starred");
            } else {
                class_list.remove("starred");
            }
        } catch (Error e) {
            warning("Failed to set classes on .email: %s", e.message);
        }
    }
    
    private static void on_context_menu(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        message_viewer.active_email = message_viewer.get_email_from_element(element);
        message_viewer.create_context_menu();
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
        message_viewer.on_menu_clicked_async(element);
    }

    private void on_menu_clicked_async(WebKit.DOM.Element element) {
        active_email = get_email_from_element(element);
        show_message_menu(element);
    }

    private static void on_unstar_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        message_viewer.on_unstar_clicked_async(element);
    }

    private void on_unstar_clicked_async(WebKit.DOM.Element element){
        active_email = get_email_from_element(element);
        on_unflag_message();
    }

    private static void on_star_clicked(WebKit.DOM.Element element, WebKit.DOM.Event event,
        MessageViewer message_viewer) {
        message_viewer.on_star_clicked_async(element);
    }

    private void on_star_clicked_async(WebKit.DOM.Element element){
        active_email = get_email_from_element(element);
        on_flag_message();
    }

    private void on_message_menu_selection_done() {
        active_email = null;
        message_menu = null;
    }

    private void on_reply_to_message() {
        reply_to_message();
    }

    private void on_reply_all_message() {
        reply_all_message();
    }

    private void on_forward_message() {
        forward_message();
    }

    private void on_mark_read_message() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_message(null, flags);
    }

    private void on_mark_unread_message() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.UNREAD);
        mark_message(flags, null);
    }

    private void on_flag_message() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_message(flags, null);
    }

    private void on_unflag_message() {
        Geary.EmailFlags flags = new Geary.EmailFlags();
        flags.add(Geary.EmailFlags.FLAGGED);
        mark_message(null, flags);
    }

    private void show_message_menu(WebKit.DOM.Element element) {
        message_menu = new Gtk.Menu();
        message_menu.selection_done.connect(on_message_menu_selection_done);

        // Reply to a message.
        Gtk.MenuItem reply_item = new Gtk.MenuItem.with_mnemonic(_("_Reply"));
        reply_item.activate.connect(on_reply_to_message);
        message_menu.append(reply_item);

        // Reply to all on a message.
        Gtk.MenuItem reply_all_item = new Gtk.MenuItem.with_mnemonic(_("Reply to _All"));
        reply_all_item.activate.connect(on_reply_all_message);
        message_menu.append(reply_all_item);

        // Forward a message.
        Gtk.MenuItem forward_item = new Gtk.MenuItem.with_mnemonic(_("_Forward"));
        forward_item.activate.connect(on_forward_message);
        message_menu.append(forward_item);

        // Separator.
        message_menu.append(new Gtk.SeparatorMenuItem());

        // Mark as read/unread.
        if (active_email.is_unread().to_boolean(false)) {
            Gtk.MenuItem mark_read_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Read"));
            mark_read_item.activate.connect(on_mark_read_message);
            message_menu.append(mark_read_item);
        } else {
            Gtk.MenuItem mark_unread_item = new Gtk.MenuItem.with_mnemonic(_("_Mark as Unread"));
            mark_unread_item.activate.connect(on_mark_unread_message);
            message_menu.append(mark_unread_item);
        }

        // Flag/unflag.
        if (active_email.is_flagged().to_boolean(false)) {
            Gtk.MenuItem unflag_item = new Gtk.MenuItem.with_mnemonic(_("Un_star"));
            unflag_item.activate.connect(on_unflag_message);
            message_menu.append(unflag_item);
        } else {
            Gtk.MenuItem flag_item = new Gtk.MenuItem.with_mnemonic(_("_Star"));
            flag_item.activate.connect(on_flag_message);
            message_menu.append(flag_item);
        }

        // Separator.
        message_menu.append(new Gtk.SeparatorMenuItem());

        // View original message source.
        Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("_View Source"));
        view_source_item.activate.connect(on_view_source);
        message_menu.append(view_source_item);

        message_menu.show_all();
        message_menu.popup(null, null, null, 0, 0);
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
                ((WebKit.DOM.HTMLElement) quote_container.query_selector(".quote")).set_inner_html(
                    text.substring(quote_start, quote_end - quote_start));
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

    private string insert_html_markup(string text) {
        try {
            // Create a workspace for manipulating the HTML.
            WebKit.DOM.Document document = get_dom_document();
            WebKit.DOM.HTMLElement container = document.create_element("div") as WebKit.DOM.HTMLElement;
            container.set_inner_html(text);
            
            // Some HTML messages like to wrap themselves in full, proper html, head, and body tags.
            // If we have that here, lets remove it since we are sticking it in our own document.
            WebKit.DOM.HTMLElement? body = container.query_selector("body") as WebKit.DOM.HTMLElement;
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
                quote_container.query_selector(".quote").append_child(blockquote_node);
                if (next_sibling == null) {
                    parent.append_child(quote_container);
                } else {
                    parent.insert_before(quote_container, next_sibling);
                }
            }

            // Now look for the signature.
            wrap_html_signature(ref container);

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
        
        output = r.replace_eval(output, -1, 0, 0, is_valid_url);
        return output.replace(" \01 ", "&lt;").replace(" \02 ", "&gt;");
    }
    
    // Validates a URL.
    // Ensures the URL begins with a valid protocol specifier.  (If not, we don't
    // want to linkify it.)
    private bool is_valid_url(MatchInfo match_info, StringBuilder result) {
        try {
            string? url = match_info.fetch(0);
            Regex r = new Regex("^(aim|apt|bitcoin|cvs|ed2k|ftp|file|finger|git|gtalk|http|https|irc|ircs|irc6|lastfm|ldap|ldaps|magnet|news|nntp|rsync|sftp|skype|smb|sms|svn|telnet|tftp|ssh|webcal|xmpp):",
                RegexCompileFlags.CASELESS);
            
            result.append(r.match(url) ? "<a href=\"%s\">%s</a>".printf(url, url) : url);
        } catch (Error e) {
            debug("URL parsing error: %s\n", e.message);
        }
        return false; // False to continue processing.
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
    
    private bool on_navigation_policy_decision_requested(WebKit.WebFrame frame,
        WebKit.NetworkRequest request, WebKit.WebNavigationAction navigation_action,
        WebKit.WebPolicyDecision policy_decision) {
        policy_decision.ignore();
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
        Gtk.Clipboard c = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
        c.set_text(hover_url, -1);
        c.store();
    }
    
    private void on_select_all() {
        select_all();
    }
    
    public void on_view_source() {
        if (active_email != null) {
            Gee.ArrayList<Geary.Email> active_list = new Gee.ArrayList<Geary.Email>();
            active_list.add(active_email);
            show_message_source(active_list);
        } else {
            show_message_source(messages);
        }
    }
    
    private void show_message_source(Gee.Collection<Geary.Email> messages) {
        StringBuilder source = new StringBuilder();
        foreach(Geary.Email email in messages)
            source.append_printf("%s%s\n\n", email.header.buffer.to_utf8(), email.body.buffer.to_utf8());
        
        try {
            string temporary_filename;
            int temporary_handle = FileUtils.open_tmp("geary-message-XXXXXX.txt",
                                                      out temporary_filename);
            FileUtils.set_contents(temporary_filename, source.str);
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
    
    private void create_context_menu() {
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
        
        // View original message source
        Gtk.MenuItem view_source_item = new Gtk.MenuItem.with_mnemonic(_("View _Source"));
        view_source_item.activate.connect(on_view_source);
        context_menu.append(view_source_item);

        // Select all.
        Gtk.MenuItem select_all_item = new Gtk.MenuItem.with_mnemonic(_("Select _All"));
        select_all_item.activate.connect(on_select_all);
        context_menu.append(select_all_item);
        
        context_menu.show_all();
        context_menu.popup(null, null, null, 0, 0);
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

