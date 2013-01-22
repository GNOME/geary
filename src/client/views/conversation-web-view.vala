/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class ConversationWebView : WebKit.WebView {
    private const string[] always_loaded_prefixes = {
        "http://www.gravatar.com/avatar/",
        "data:"
    };
    
    private const string USER_CSS = "user-message.css";
    private const string STYLE_NAME = "STYLE";

    public bool load_external_images { get; private set; default = false; }

    // HTML element that contains message DIVs.
    public WebKit.DOM.HTMLDivElement? container { get; private set; default = null; }

    private Gee.ArrayList<string>? external_images_uri = null;
    private FileMonitor? user_style_monitor = null;

    public signal void image_load_requested();

    public signal void link_selected(string link);

    public ConversationWebView() {
        // Set defaults.
        set_border_width(0);
        
        WebKit.WebSettings config = new WebKit.WebSettings();
        config.enable_scripts = false;
        config.enable_java_applet = false;
        config.enable_plugins = false;
        config.enable_default_context_menu = false; // Deprecated, still needed for Precise
        settings = config;
        
        // Hook up signals.
        load_finished.connect(on_load_finished);
        resource_request_starting.connect(on_resource_request_starting);
        navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        
        // Load the HTML into WebKit.
        // Note: load_finished signal MUST be hooked up before this call.
        string html_text = GearyApplication.instance.read_theme_file("message-viewer.html") ?? "";
        load_string(html_text, "text/html", "UTF8", "");
    }
    
    public override bool query_tooltip(int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
        // Disable tooltips from within WebKit itself.
        return false;
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
        if (!is_always_loaded(uri) && !(is_image(uri) && load_external_images))
            request.set_uri("about:blank");
    }

    public void set_external_images_uris(Gee.ArrayList<string> uris) {
        external_images_uri = uris;
    }

    public bool is_image(string? uri) {
        if (Geary.String.is_empty_or_whitespace(uri))
            return false;

        if (uri.has_prefix("data:image/"))
            return true;

        // check if external_images_uri is null in case this is called before a page is loaded
        return (external_images_uri != null) ? (uri in external_images_uri) : false;
    }

    private bool is_always_loaded(string? uri) {
        if (uri == null)
            return false;
        
        foreach (string prefix in always_loaded_prefixes) {
            if (uri.has_prefix(prefix))
                return true;
        }
        
        return false;
    }
    
    public void apply_load_external_images(bool load_external_images) {
        this.load_external_images = load_external_images;
        
        // Refreshing the images would do nothing in this case--the resource has already been
        // loaded, so no additional resource request will be sent.
        if (load_external_images == false)
            return;
        
        // We can't simply set load_external_images to true before refreshing, then set it back to
        // false afterwards. If one of the images' sources is redirected, an additional resource
        // request will come after we reset load_external_images to false.
        try {
            WebKit.DOM.Document document = get_dom_document();
            WebKit.DOM.NodeList nodes = document.query_selector_all("img");
            for (ulong i = 0; i < nodes.length; i++) {
                WebKit.DOM.Element? element = nodes.item(i) as WebKit.DOM.Element;
                if (element == null)
                    continue;
                
                if (!element.has_attribute("src"))
                    continue;
                
                string src = element.get_attribute("src");
                if (Geary.String.is_empty_or_whitespace(src) || is_always_loaded(src))
                    continue;
                
                // Refresh the image source. Requests are denied when load_external_images
                // is false, so we need to force webkit to send the request again.
                element.set_attribute("src", src);
            }
        } catch (Error err) {
            debug("Error refreshing images: %s", err.message);
        }
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
        set_icon_src("#email_template .menu .icon", "go-down");
        set_icon_src("#email_template .starred .icon", "starred");
        set_icon_src("#email_template .unstarred .icon", "non-starred-grey");
        set_icon_src("#email_template .attachment.icon", "mail-attachment");
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
    
    public void set_image_src(WebKit.DOM.HTMLImageElement img, string mime_type, string filename,
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
    
    public void set_data_url(WebKit.DOM.HTMLImageElement img, string mime_type, uint8[] content)
        throws Error {
        img.set_attribute("src", "data:%s;base64,%s".printf(mime_type, Base64.encode(content)));
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
}

