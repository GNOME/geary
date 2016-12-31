/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

protected errordomain JSError { TYPE }

public class ClientWebView : WebKit.WebView {


    /** URI Scheme and delimiter for images loaded by Content-ID. */
    public const string CID_PREFIX = "cid:";

    private const string PREFERRED_HEIGHT_MESSAGE = "preferredHeightChanged";
    private const string REMOTE_IMAGE_LOAD_BLOCKED_MESSAGE = "remoteImageLoadBlocked";
    private const string SELECTION_CHANGED_MESSAGE = "selectionChanged";

    private const double ZOOM_DEFAULT = 1.0;
    private const double ZOOM_FACTOR = 0.1;

    private static WebKit.UserScript? script = null;
    private static WebKit.UserScript? allow_remote_images = null;

    /**
     * Initialises WebKit.WebContext for use by the client.
     */
    public static void init_web_context(File web_extension_dir,
                                        bool enable_logging) {
        WebKit.WebContext context = WebKit.WebContext.get_default();
        context.set_process_model(WebKit.ProcessModel.SHARED_SECONDARY_PROCESS);
        context.set_cache_model(WebKit.CacheModel.DOCUMENT_BROWSER);
        context.register_uri_scheme("cid", (req) => {
                ClientWebView? view = req.get_web_view() as ClientWebView;
                if (view != null) {
                    view.handle_cid_request(req);
                }
            });
        context.initialize_web_extensions.connect((context) => {
                context.set_web_extensions_directory(
                    web_extension_dir.get_path()
                );
                context.set_web_extensions_initialization_user_data(
                    new Variant.boolean(enable_logging)
                );
            });
    }

    /**
     * Loads static resources used by ClientWebView.
     */
    public static void load_scripts()
        throws Error {
        ClientWebView.script = load_app_script(
            "client-web-view.js"
        );
        ClientWebView.allow_remote_images = load_app_script(
            "client-web-view-allow-remote-images.js"
        );
    }

    /** Loads an application-specific WebKit stylesheet. */
    protected static WebKit.UserStyleSheet load_app_stylesheet(string name)
        throws Error {
        return new WebKit.UserStyleSheet(
            GioUtil.read_resource(name),
            WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserStyleLevel.USER,
            null,
            null
        );
    }

    /** Loads a user stylesheet, if any. */
    protected static WebKit.UserStyleSheet? load_user_stylesheet(File name) {
        WebKit.UserStyleSheet? user_stylesheet = null;
        try {
            Geary.Memory.FileBuffer buf = new Geary.Memory.FileBuffer(name, true);
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

    /** Loads an application-specific WebKit JavaScript script. */
    protected static WebKit.UserScript load_app_script(string name)
        throws Error {
        return new WebKit.UserScript(
            GioUtil.read_resource(name),
            WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserScriptInjectionTime.START,
            null,
            null
        );
    }

    protected static bool get_bool_result(WebKit.JavascriptResult result)
        throws JSError {
        JS.GlobalContext context = result.get_global_context();
        JS.Value value = result.get_value();
        return context.to_boolean(value);
        // XXX unref result?
    }

    protected static int get_int_result(WebKit.JavascriptResult result)
        throws JSError {
        JS.GlobalContext context = result.get_global_context();
        JS.Value value = result.get_value();
        if (!context.is_number(value)) {
            throw new JSError.TYPE("Value is not a number");
        }
        JS.Value? err = null;
        return (int) context.to_number(value, out err);
        // XXX check err
        // XXX unref result?
    }

    protected static string? get_string_result(WebKit.JavascriptResult result)
        throws JSError {
        JS.GlobalContext context = result.get_global_context();
        JS.Value js_str_value = result.get_value();
        JS.Value? err = null;
        JS.String js_str = context.to_string_copy(js_str_value, out err);
        // XXX check err
        int len = js_str.get_maximum_utf8_cstring_size();
        string value = string.nfill(len, 0);
        js_str.get_utf8_cstring(value, len);
        js_str.release();
        debug("Got string: %s", value);
        return value;
        // XXX unref result?
    }

    private static inline uint to_wk2_font_size(Pango.FontDescription font) {
        Gdk.Screen? screen = Gdk.Screen.get_default();
        double dpi = screen != null ? screen.get_resolution() : 96.0;
        double size = font.get_size();
        if (!font.get_size_is_absolute()) {
            size = size / Pango.SCALE;
        }
        return (uint) (size * dpi / 72.0);
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
            settings.default_font_size = to_wk2_font_size(font);
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
            settings.default_monospace_font_size = to_wk2_font_size(font);
            set_settings(settings);
        }
    }

    private Gee.Map<string,Geary.Memory.Buffer> cid_resources =
        new Gee.HashMap<string,Geary.Memory.Buffer>();

    private int preferred_height = 0;


    /** Emitted when the web view's selection has changed. */
    public signal void selection_changed(bool has_selection);

    /** Emitted when a user clicks a link in this web view. */
    public signal void link_activated(string uri);

    /** Emitted when the web view has loaded an inline part. */
    public signal void inline_resource_loaded(string cid);

    /** Emitted when a remote image load was disallowed. */
    public signal void remote_image_load_blocked();


    public ClientWebView(WebKit.UserContentManager? custom_manager = null) {
        WebKit.Settings setts = new WebKit.Settings();
        setts.allow_modal_dialogs = false;
        setts.default_charset = "UTF-8";
        setts.enable_developer_extras = Args.inspector;
        setts.enable_fullscreen = false;
        setts.enable_html5_database = false;
        setts.enable_html5_local_storage = false;
        setts.enable_java = false;
        setts.enable_javascript = true;
        setts.enable_media_stream = false;
        setts.enable_offline_web_application_cache = false;
        setts.enable_page_cache = false;
        setts.enable_plugins = false;
        setts.javascript_can_access_clipboard = true;

        WebKit.UserContentManager content_manager =
             custom_manager ?? new WebKit.UserContentManager();
        content_manager.add_script(ClientWebView.script);

        Object(user_content_manager: content_manager, settings: setts);

        // XXX get the allow prefix from the extension somehow

        this.decide_policy.connect(on_decide_policy);
        this.load_changed.connect((web_view, event) => {
                if (event == WebKit.LoadEvent.FINISHED) {
                    this.is_loaded = true;
                }
            });
        this.web_process_crashed.connect(() => {
                debug("Web process crashed");
                return Gdk.EVENT_PROPAGATE;
            });

        content_manager.script_message_received[PREFERRED_HEIGHT_MESSAGE].connect(
            (result) => {
                try {
                    this.preferred_height = get_int_result(result);
                    queue_resize();
                } catch (JSError err) {
                    debug("Could not get preferred height: %s", err.message);
                }
            });
        content_manager.script_message_received[REMOTE_IMAGE_LOAD_BLOCKED_MESSAGE].connect(
            (result) => {
                remote_image_load_blocked();
            });
        content_manager.script_message_received[SELECTION_CHANGED_MESSAGE].connect(
            (result) => {
                try {
                    selection_changed(get_bool_result(result));
                } catch (JSError err) {
                    debug("Could not get selection content: %s", err.message);
                }
            });

        register_message_handler(PREFERRED_HEIGHT_MESSAGE);
        register_message_handler(REMOTE_IMAGE_LOAD_BLOCKED_MESSAGE);
        register_message_handler(SELECTION_CHANGED_MESSAGE);

        GearyApplication.instance.config.bind(Configuration.CONVERSATION_VIEWER_ZOOM_KEY, this, "zoom_level");
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
     * Allows loading any remote images found during page load.
     *
     * This must be called before HTML content is loaded to have any
     * effect.
     */
    public void allow_remote_image_loading() {
        // Use a separate script here since we need to update the
        // value of window.geary.allow_remote_image_loading after it
        // was first created by client-web-view.js (which is loaded at
        // the start of page load), but before the page load is
        // started (so that any remote images present are actually
        // loaded).
        this.user_content_manager.add_script(ClientWebView.allow_remote_images);
    }

    /**
     * Load any remote images previously that were blocked.
     */
    public void load_remote_images() {
        run_javascript.begin("geary.loadRemoteImages();", null);
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

    // XXX Surely since we are doing height-for-width, we should be
    // overriding get_preferred_height_for_width here, but that
    // doesn't seem to work.
    public override void get_preferred_height(out int minimum_height,
                                              out int natural_height) {
        minimum_height = natural_height = this.preferred_height;
    }

    // Overridden since we always what the view to be sized according
    // to the available space in the parent, not by the width of the
    // web view.
    public override void get_preferred_width(out int minimum_height,
                                             out int natural_height) {
        minimum_height = natural_height = 0;
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

    protected inline void register_message_handler(string name) {
        if (!get_user_content_manager().register_script_message_handler(name)) {
            debug("Failed to register script message handler: %s", name);
        }
    }

    // Only allow string-based page loads, and notify but ignore if
    // the user attempts to click on a link. Deny everything else.
    private bool on_decide_policy(WebKit.WebView view,
                                  WebKit.PolicyDecision policy,
                                  WebKit.PolicyDecisionType type) {
        if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION ||
            type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
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
