/* 
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class ConversationWebView : StylishWebView {
    private const string[] always_loaded_prefixes = {
        "https://secure.gravatar.com/avatar/",
        "data:"
    };
    
    private const string USER_CSS = "user-message.css";
    private const string STYLE_NAME = "STYLE";
    private const string PREVENT_HIDE_STYLE = "nohide";

    public string allow_prefix { get; private set; default = ""; }

    // We need to wrap zoom_level (type float) because we cannot connect with float
    // with double (cf https://bugzilla.gnome.org/show_bug.cgi?id=771534)
    public double zoom_level_wrap {
        get { return zoom_level; }
        set { if (zoom_level != (float)value) zoom_level = (float)value; }
    }

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

        GearyApplication.instance.config.bind(Configuration.CONVERSATION_VIEWER_ZOOM_KEY, this, "zoom_level_wrap");
        notify["zoom-level"].connect(() => { zoom_level_wrap = zoom_level; });
    }
    
    public override bool query_tooltip(int x, int y, bool keyboard_tooltip, Gtk.Tooltip tooltip) {
        // Disable tooltips from within WebKit itself.
        return false;
    }
    
    // Overridden to get the correct height from get_preferred_height.
    public new void get_preferred_size(out Gtk.Requisition minimum_size,
                                       out Gtk.Requisition natural_size) {
        base.get_preferred_size(out minimum_size, out natural_size);

        int minimum_height = 0;
        int natural_height = 0;
        get_preferred_height(out minimum_height, out natural_height);
        
        minimum_size.height = minimum_height;
        natural_size.height = natural_height;
    }

    // Overridden since WebKitGTK+ 2.4.10 at least doesn't want to
    // report a useful height. In combination with the rules from
    // theming/message-viewer.css we can get an accurate idea of
    // the actual height of the content from the BODY element, but
    // only once loaded.
    public override void get_preferred_height(out int minimum_height,
                                              out int natural_height) {
        int preferred_height = 0;
        if (load_status == WebKit.LoadStatus.FINISHED) {
            preferred_height = (int) get_dom_document().get_body().offset_height;
        }
        minimum_height = natural_height = preferred_height;
    }

    public WebKit.DOM.HTMLDivElement create_div() throws Error {
        return get_dom_document().create_element("div") as WebKit.DOM.HTMLDivElement;
    }

    public bool is_always_loaded(string uri) {
        foreach (string prefix in always_loaded_prefixes) {
            if (uri.has_prefix(prefix))
                return true;
        }
        
        return false;
    }
    
    private void on_resource_request_starting(WebKit.WebFrame web_frame,
        WebKit.WebResource web_resource, WebKit.NetworkRequest request,
        WebKit.NetworkResponse? response) {
        if (response != null) {
            // A request that was previously approved resulted in a redirect.
            return;
        }

        string? uri = request.get_uri();
        if (uri != null && !is_always_loaded(uri)) {
            if (uri.has_prefix(allow_prefix))
                request.set_uri(uri.substring(allow_prefix.length));
            else
                request.set_uri("about:blank");
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
        
        on_document_font_changed();
        load_user_style();
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
    
    private bool on_navigation_policy_decision_requested(WebKit.WebFrame frame,
        WebKit.NetworkRequest request, WebKit.WebNavigationAction navigation_action,
        WebKit.WebPolicyDecision policy_decision) {
        policy_decision.ignore();
        
        // Other policy-decisions may be requested for various reasons. The existence of an iframe,
        // for example, causes a policy-decision request with an "OTHER" reason. We don't want to
        // open a webpage in the browser just because an email contains an iframe.
        if (navigation_action.reason == WebKit.WebNavigationReason.LINK_CLICKED) {
            link_selected(request.uri);
        }
        return true;
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
    
}

