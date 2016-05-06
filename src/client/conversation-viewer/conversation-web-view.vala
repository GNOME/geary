/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : StylishWebView {
    private const string[] always_loaded_prefixes = {
        "http://www.gravatar.com/avatar/",
        "data:"
    };
    
    private const string USER_CSS = "user-message.css";
    private const string STYLE_NAME = "STYLE";
    private const string PREVENT_HIDE_STYLE = "nohide";
    private Gdk.RGBA conversation_icon_color;
    
    // HTML element that contains message DIVs.
    public WebKit.DOM.HTMLDivElement? container { get; private set; default = null; }
    
    public string allow_prefix { get; private set; default = ""; }

    private FileMonitor? user_style_monitor = null;

    public signal void link_selected(string link);

    public ConversationWebView() {
        // Set defaults.
        set_border_width(0);
        allow_prefix = random_string(10) + ":";
        
        WebKit.WebSettings config = settings;
        config.enable_scripts = false;
        config.enable_java_applet = false;
        config.enable_plugins = false;
        config.enable_developer_extras = Args.inspector;
        settings = config;
        
        // Hook up signals.
        load_finished.connect(on_load_finished);
        resource_request_starting.connect(on_resource_request_starting);
        navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        web_inspector.inspect_web_view.connect(activate_inspector);
        document_font_changed.connect(on_document_font_changed);
        scroll_event.connect(on_scroll_event);
        
        // Load the HTML into WebKit.
        // Note: load_finished signal MUST be hooked up before this call.
        string html_text = GearyApplication.instance.read_theme_file("message-viewer.html") ?? "";
        load_string(html_text, "text/html", "UTF8", "");
    }
    
    public override bool query_tooltip(int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
        // Disable tooltips from within WebKit itself.
        return false;
    }
    
    private bool on_scroll_event(Gdk.EventScroll event) {
        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
            double dir = 0;
            if (event.direction == Gdk.ScrollDirection.UP)
                dir = -1;
            else if (event.direction == Gdk.ScrollDirection.DOWN)
                dir = 1;
            else if (event.direction == Gdk.ScrollDirection.SMOOTH)
                dir = event.delta_y;
            
            if (dir < 0) {
                zoom_in();
                return true;
            } else if (dir > 0) {
                zoom_out();
                return true;
            }
        }
        return false;
    }
    
    public void hide_element_by_id(string element_id) throws Error {
        get_dom_document().get_element_by_id(element_id).set_attribute("style", "display:none");
    }
    
    public void show_element_by_id(string element_id) throws Error {
        get_dom_document().get_element_by_id(element_id).set_attribute("style", "display:block");
    }
    
    // Scrolls back up to the top.
    public void scroll_reset() {
        get_dom_document().get_default_view().scroll(0, 0);
    }
    
    private void on_resource_request_starting(WebKit.WebFrame web_frame,
        WebKit.WebResource web_resource, WebKit.NetworkRequest request,
        WebKit.NetworkResponse? response) {
        if (response != null) {
            // A request that was previously approved resulted in a redirect.
            return;
        }

        string? uri = request.get_uri();
        if (!is_always_loaded(uri)) {
            if (uri.has_prefix(allow_prefix))
                request.set_uri(uri.substring(allow_prefix.length));
            else
                request.set_uri("about:blank");
        }
    }
    
    public bool is_always_loaded(string? uri) {
        if (uri == null)
            return true;
        
        foreach (string prefix in always_loaded_prefixes) {
            if (uri.has_prefix(prefix))
                return true;
        }
        
        return false;
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
        
        on_document_font_changed();
        load_user_style();
        
        // Grab the HTML container.
        WebKit.DOM.Element? _container = get_dom_document().get_element_by_id("message_container");
        assert(_container != null);
        container = _container as WebKit.DOM.HTMLDivElement;
        assert(container != null);
        
        conversation_icon_color.parse("#888888");
        // Load the icons.
        set_icon_src("#email_template .menu .icon", "go-down-symbolic");
        set_icon_src("#email_template .starred .icon", "starred-symbolic");
        set_icon_src("#email_template .unstarred .icon", "non-starred-symbolic");
        set_icon_src("#email_template .attachment.icon", "mail-attachment-symbolic");
        set_icon_src("#email_template .close_show_images", "close-symbolic");
        set_icon_src("#link_warning_template .close_link_warning", "close-symbolic");
    }
    
    private void on_document_font_changed() {
        string document_css = "";
        if (document_font != null) {
            string font_family = Pango.FontDescription.from_string(document_font).get_family();
            document_css = @".email .body { font-family: $font_family; font-size: medium; }\n";
        }
        
        WebKit.DOM.Document document = get_dom_document();
        WebKit.DOM.Element style_element = document.get_element_by_id("default_fonts");
        if (style_element == null)  // Not yet loaded
            return;
        
        ulong n = style_element.child_nodes.length;
        try {
            for (int i = 0; i < n; i++)
                style_element.remove_child(style_element.first_child);
            
            WebKit.DOM.Text text_node = document.create_text_node(document_css);
            style_element.append_child(text_node);
        } catch (Error error) {
            debug("Error updating default font style: %s", error.message);
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
            // Load icon.
            uint8[]? icon_content = null;
            Gdk.Pixbuf? pixbuf = IconFactory.instance.load_symbolic_colored(icon_name, 16, 
                conversation_icon_color);
            if (pixbuf != null)
                pixbuf.save_to_buffer(out icon_content, "png"); // Load as PNG.
            
            if (icon_content == null || icon_content.length == 0)
                return;
            
            // Save length before transferring ownership (which frees the array)
            int icon_length = icon_content.length;
            Geary.Memory.ByteBuffer buffer = new Geary.Memory.ByteBuffer.take((owned) icon_content,
                icon_length);
            
            // Then set the source to a data url.
            WebKit.DOM.HTMLImageElement img = Util.DOM.select(get_dom_document(), selector)
                as WebKit.DOM.HTMLImageElement;
            img.set_attribute("src", assemble_data_uri("image/png", buffer));
        } catch (Error error) {
            warning("Failed to load icon '%s': %s", icon_name, error.message);
        }
    }
    
    public void set_attachment_src(WebKit.DOM.HTMLImageElement img, Geary.Mime.ContentType content_type,
        string filename, int maxwidth, int maxheight = -1) {
        if( maxheight == -1 ){
            maxheight = maxwidth;
        }
        
        try {
            // If the file is an image, use it. Otherwise get the icon for this mime_type.
            string gio_content_type = ContentType.from_mime_type(content_type.get_mime_type());
            
            Gdk.Pixbuf pixbuf;
            if (content_type.has_media_type("image")) {
                // Get a thumbnail for the image.
                // TODO Generate and save the thumbnail when extracting the attachments rather than
                // when showing them in the viewer.
                img.get_class_list().add("thumbnail");
                pixbuf = new Gdk.Pixbuf.from_file_at_scale(filename, maxwidth, maxheight, true);
                pixbuf = pixbuf.apply_embedded_orientation();
            } else {
                // Load the icon for this mime type.
                ThemedIcon icon = ContentType.get_icon(gio_content_type) as ThemedIcon;
                string icon_filename = IconFactory.instance.lookup_icon(icon.names[0], maxwidth)
                    .get_filename();
                pixbuf = new Gdk.Pixbuf.from_file_at_scale(icon_filename, maxwidth, maxheight, true);
            }
            
            // convert to PNG and assemble IMG src as a data: URI
            uint8[] content;
            pixbuf.save_to_buffer(out content, "png");
            
            // Then set the source to a data url.
            // Save length before transferring ownership (which frees the array)
            int content_length = content.length;
            Geary.Memory.Buffer buffer = new Geary.Memory.ByteBuffer.take((owned) content,
                content_length);
            
            img.set_attribute("src", assemble_data_uri("image/png", buffer));
        } catch (Error error) {
            warning("Failed to load image '%s': %s", filename, error.message);
        }
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
    
    public WebKit.DOM.HTMLDivElement create_div() throws Error {
        return get_dom_document().create_element("div") as WebKit.DOM.HTMLDivElement;
    }

    public void scroll_to_element(WebKit.DOM.HTMLElement element) {
        get_dom_document().get_default_view().scroll(element.offset_left, element.offset_top);
    }
    
    private unowned WebKit.WebView activate_inspector(WebKit.WebInspector inspector, WebKit.WebView target_view) {
        Gtk.Window window = new Gtk.Window();
        window.set_default_size(600, 600);
        window.set_title(_("%s - Conversation Inspector").printf(GearyApplication.NAME));
        Gtk.ScrolledWindow scrolled = new Gtk.ScrolledWindow(null, null);
        WebKit.WebView inspector_view = new WebKit.WebView();
        scrolled.add(inspector_view);
        window.add(scrolled);
        window.show_all();
        window.delete_event.connect(() => {
            inspector.close();
            return false;
        });
        
        unowned WebKit.WebView r = inspector_view;
        return r;
    }
    
    public void allow_collapsing(bool allow) {
        try {
            if (allow)
                get_dom_document().get_body().get_class_list().remove("nohide");
            else
                get_dom_document().get_body().get_class_list().add("nohide");
        } catch (Error error) {
            debug("Error setting body class: %s", error.message);
        }
    }
}

