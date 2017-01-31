/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class ClientWebView : WebKit.WebView {


    public const string CID_PREFIX = "cid:";

    private const double ZOOM_DEFAULT = 1.0;
    private const double ZOOM_FACTOR = 0.1;

    protected static WebKit.UserStyleSheet load_app_stylesheet(GearyApplication app,
                                                               string name)
        throws Error {
        return new WebKit.UserStyleSheet(
            app.read_resource(name),
            WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserStyleLevel.USER,
            null,
            null
        );
    }

    protected static WebKit.UserStyleSheet? load_user_stylesheet(GearyApplication app,
                                                                 string name) {
        File stylesheet = app.get_user_config_directory().get_child(name);
        WebKit.UserStyleSheet? user_stylesheet = null;
        try {
            Geary.Memory.FileBuffer buf =
                new Geary.Memory.FileBuffer(stylesheet, true);
            user_stylesheet = new WebKit.UserStyleSheet(
                buf.get_valid_utf8(),
                WebKit.UserContentInjectedFrames.ALL_FRAMES,
                WebKit.UserStyleLevel.USER,
                null,
                null
            );
        } catch (IOError.NOT_FOUND err) {
            warning("User CSS file does not exist: %s", err.message);
        } catch (Error err) {
            warning("Failed to load user CSS file: %s", err.message);
        }
        return user_stylesheet;
    }


    public bool is_loaded { get; private set; default = false; }
    public string allow_prefix { get; private set; default = ""; }

    private string _document_font;
    public string document_font {
        get {
            return _document_font;
        }
        set {
            _document_font = value;
            Pango.FontDescription font = Pango.FontDescription.from_string(value);
            WebKit.Settings settings = get_settings();
            settings.default_font_family = font.get_family();
            settings.default_font_size = font.get_size() / Pango.SCALE;
            set_settings(settings);
        }
    }

    private string _monospace_font;
    public string monospace_font {
        get {
            return _monospace_font;
        }
        set {
            _monospace_font = value;
            Pango.FontDescription font = Pango.FontDescription.from_string(value);
            WebKit.Settings settings = get_settings();
            settings.monospace_font_family = font.get_family();
            settings.default_monospace_font_size = font.get_size() / Pango.SCALE;
            set_settings(settings);
        }
    }

    // We need to wrap zoom_level (type float) because we cannot connect with float
    // with double (cf https://bugzilla.gnome.org/show_bug.cgi?id=771534)
    public double zoom_level_wrap {
        get { return zoom_level; }
        set { if (zoom_level != (float)value) zoom_level = (float)value; }
    }

    private Gee.Map<string,Geary.Memory.Buffer> cid_resources =
        new Gee.HashMap<string,Geary.Memory.Buffer>();


    /** Emitted when a user clicks a link in this web view. */
    public signal void link_activated(string uri);

    /** Emitted when the web view has loaded an inline part. */
    public signal void inline_resource_loaded(string cid);


    public ClientWebView(WebKit.UserContentManager? content_manager = null) {
        WebKit.Settings setts = new WebKit.Settings();
        setts.enable_javascript = false;
        setts.enable_java = false;
        setts.enable_plugins = false;
        setts.enable_developer_extras = Args.inspector;
        setts.javascript_can_access_clipboard = true;

        Object(user_content_manager: content_manager, settings: setts);

        // XXX get the allow prefix from the extension somehow

        this.decide_policy.connect(on_decide_policy);
        this.load_changed.connect((web_view, event) => {
                if (event == WebKit.LoadEvent.FINISHED) {
                    this.is_loaded = true;
                }
            });

        GearyApplication.instance.config.bind(Configuration.CONVERSATION_VIEWER_ZOOM_KEY, this, "zoom_level_wrap");
        this.notify["zoom-level"].connect(() => { zoom_level_wrap = zoom_level; });
        this.scroll_event.connect(on_scroll_event);

        Settings system_settings = GearyApplication.instance.config.gnome_interface;
        system_settings.bind("document-font-name", this, "document-font", SettingsBindFlags.DEFAULT);
        system_settings.bind("monospace-font-name", this, "monospace-font", SettingsBindFlags.DEFAULT);
    }

    /**
     * Adds an inline resource that may be accessed via a cid:id url.
     */
    public void add_inline_resource(string id, Geary.Memory.Buffer buf) {
        this.cid_resources[id] = buf;
    }

    /**
     * Adds a set of inline resource that may be accessed via a cid:id url.
     */
    public void add_inline_resources(Gee.Map<string,Geary.Memory.Buffer> res) {
        this.cid_resources.set_all(res);
    }

    /**
     * Selects all content in the web view.
     */
    public void select_all() {
        execute_editing_command(WebKit.EDITING_COMMAND_SELECT_ALL);
    }

    /**
     * Sends a copy command to the web view.
     */
    public void copy_clipboard() {
        execute_editing_command(WebKit.EDITING_COMMAND_CUT);
    }

    public bool can_copy_clipboard() {
        // can_execute_editing_command.begin(
        //     WebKit.EDITING_COMMAND_COPY,
        //     null,
        //     (obj, res) => {
        //         return can_execute_editing_command.end(res);
        //     });
        return false;
    }

    public void reset_zoom() {
        this.zoom_level == ZOOM_DEFAULT;
    }

    public void zoom_in() {
        this.zoom_level += (this.zoom_level * ZOOM_FACTOR);
    }

    public void zoom_out() {
        this.zoom_level -= (this.zoom_level * ZOOM_FACTOR);
    }

    internal void handle_cid_request(WebKit.URISchemeRequest request) {
        string cid = request.get_uri().substring(CID_PREFIX.length);
        Geary.Memory.Buffer? buf = this.cid_resources[cid];
        if (buf != null) {
            request.finish(buf.get_input_stream(), buf.size, null);
            inline_resource_loaded(cid);
        } else {
            request.finish_error(
                new FileError.NOENT("Unknown CID: %s".printf(cid))
            );
        }
    }

    // Only allow string-based page loads, and notify but ignore if
    // the user attempts to click on a link. Deny everything else.
    private bool on_decide_policy(WebKit.WebView view,
                                  WebKit.PolicyDecision policy,
                                  WebKit.PolicyDecisionType type) {
        if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION) {
            WebKit.NavigationPolicyDecision nav_policy =
                (WebKit.NavigationPolicyDecision) policy;
            switch (nav_policy.get_navigation_type()) {
            case WebKit.NavigationType.OTHER:
                // HTML string load, and maybe other random things?
                policy.use();
                break;

            case WebKit.NavigationType.LINK_CLICKED:
                // Let the app know a user activated a link, but don't
                // try to load it ourselves.
                link_activated(nav_policy.request.uri);
                policy.ignore();
                break;

            default:
                policy.ignore();
                break;
            }
        } else {
            policy.ignore();
        }
        return Gdk.EVENT_STOP;
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

}

