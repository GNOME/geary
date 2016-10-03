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

    public string allow_prefix { get; private set; default = ""; }

    // We need to wrap zoom_level (type float) because we cannot connect with float
    // with double (cf https://bugzilla.gnome.org/show_bug.cgi?id=771534)
    public double zoom_level_wrap {
        get { return zoom_level; }
        set { if (zoom_level != (float)value) zoom_level = (float)value; }
    }

    public bool is_height_valid = false;

    public signal void link_selected(string link);

    public ConversationWebView() {
        // Set defaults.
        set_border_width(0);
        allow_prefix = random_string(10) + ":";

        File user_css = GearyApplication.instance.get_user_config_directory().get_child(USER_CSS);
        // Print out a debug line here if the user CSS file exists, so
        // we get warning about it when debugging visual issues.
        user_css.query_info_async.begin(
            FileAttribute.STANDARD_TYPE,
            FileQueryInfoFlags.NONE,
            Priority.DEFAULT_IDLE,
            null,
            (obj, res) => {
                try {
                    user_css.query_info_async.end(res);
                    debug("User CSS file exists: %s", USER_CSS);
                } catch (Error e) {
                    // No problem, file does not exist
                }
            });

        WebKit.WebSettings config = settings;
        config.enable_scripts = false;
        config.enable_java_applet = false;
        config.enable_plugins = false;
        config.enable_developer_extras = Args.inspector;
        config.user_stylesheet_uri = user_css.get_uri();
        settings = config;

        // Hook up signals.
        resource_request_starting.connect(on_resource_request_starting);
        navigation_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        new_window_policy_decision_requested.connect(on_navigation_policy_decision_requested);
        web_inspector.inspect_web_view.connect(activate_inspector);
        scroll_event.connect(on_scroll_event);

        GearyApplication.instance.config.bind(Configuration.CONVERSATION_VIEWER_ZOOM_KEY, this, "zoom_level_wrap");
        notify["zoom-level"].connect(() => { zoom_level_wrap = zoom_level; });
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
    // ui/conversation-web-view.css we can get an accurate idea of
    // the actual height of the content from the BODY element, but
    // only once loaded.
    public override void get_preferred_height(out int minimum_height,
                                              out int natural_height) {
        // Silence the "How does the code know the size to allocate?"
        // warning in GTK 3.20-ish.
        base.get_preferred_height(out minimum_height, out natural_height);

        int preferred_height = 0;
        if (load_status == WebKit.LoadStatus.FINISHED) {
            WebKit.DOM.Element html =
                get_dom_document().get_document_element();
            preferred_height = (int) html.offset_height;
        }

        // XXX Currently, for some messages the WebView will report
        // very large offset heights, causing GDK and X allocation
        // failures/warnings. If we get one, log it and limit it.  A
        // value of ~22000 was crashing my xserver with a WebView
        // width of around 745.
        const int MAX = 15000;
        this.is_height_valid = preferred_height > MAX;
        if (this.is_height_valid) {
            warning("WebView height reported as %i/%li, clamping",
                    preferred_height,
                    get_dom_document().get_body().offset_height);
            preferred_height = MAX;
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

