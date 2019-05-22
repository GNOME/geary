/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Base class for all WebKit2 WebView instances used by the Geary client.
 *
 * This provides common functionality expected by the client for
 * displaying HTML, such as common WebKit settings, desktop font
 * integration, Inspector support, and remote and inline image
 * handling.
 */
public abstract class ClientWebView : WebKit.WebView, Geary.BaseInterface {


    /** URI Scheme and delimiter for internal resource loads. */
    public const string INTERNAL_URL_PREFIX = "geary:";

    /** URI for internal message body page loads. */
    public const string INTERNAL_URL_BODY = INTERNAL_URL_PREFIX + "body";

    /** URI Scheme and delimiter for images loaded by Content-ID. */
    public const string CID_URL_PREFIX = "cid:";

    // WebKit message handler names
    private const string COMMAND_STACK_CHANGED = "commandStackChanged";
    private const string CONTENT_LOADED = "contentLoaded";
    private const string DOCUMENT_MODIFIED = "documentModified";
    private const string PREFERRED_HEIGHT_CHANGED = "preferredHeightChanged";
    private const string REMOTE_IMAGE_LOAD_BLOCKED = "remoteImageLoadBlocked";
    private const string SELECTION_CHANGED = "selectionChanged";

    private const double ZOOM_DEFAULT = 1.0;
    private const double ZOOM_FACTOR = 0.1;
    private const double ZOOM_MAX = 2.0;
    private const double ZOOM_MIN = 0.5;

    private const string USER_CSS = "user-style.css";
    private const string USER_CSS_LEGACY = "user-message.css";



    // Workaround WK binding ctor not accepting any args
    private class WebsiteDataManager : WebKit.WebsiteDataManager {

        public WebsiteDataManager(string base_cache_directory) {
            // Use the cache dir for both cache and data since a)
            // emails shouldn't be storing data anyway, and b) so WK
            // doesn't use the default, shared data dir.
            Object(
                base_cache_directory: base_cache_directory,
                base_data_directory: base_cache_directory
            );
        }

    }


    private static WebKit.WebContext? default_context = null;

    private static WebKit.UserStyleSheet? user_stylesheet = null;

    private static WebKit.UserScript? script = null;
    private static WebKit.UserScript? allow_remote_images = null;


    /**
     * Initialises WebKit.WebContext for use by the client.
     */
    public static void init_web_context(Configuration config,
                                        File web_extension_dir,
                                        File cache_dir) {
        WebsiteDataManager data_manager = new WebsiteDataManager(cache_dir.get_path());
        WebKit.WebContext context = new WebKit.WebContext.with_website_data_manager(data_manager);
        // Use a shared process so we don't spawn N WebProcess instances
        // when showing N messages in a conversation.
        context.set_process_model(WebKit.ProcessModel.SHARED_SECONDARY_PROCESS);
        // Use the doc viewer model since each web view instance only
        // ever shows a single HTML document.
        context.set_cache_model(WebKit.CacheModel.DOCUMENT_VIEWER);

        context.register_uri_scheme("cid", (req) => {
                ClientWebView? view = req.get_web_view() as ClientWebView;
                if (view != null) {
                    view.handle_cid_request(req);
                }
            });
        context.register_uri_scheme("geary", (req) => {
                ClientWebView? view = req.get_web_view() as ClientWebView;
                if (view != null) {
                    view.handle_internal_request(req);
                }
            });
        context.initialize_web_extensions.connect((context) => {
                context.set_web_extensions_directory(
                    web_extension_dir.get_path()
                );
                context.set_web_extensions_initialization_user_data(
                    new Variant.boolean(config.enable_debug)
                );
            });

        update_spellcheck(context, config);
        config.settings.changed[Configuration.SPELL_CHECK_LANGUAGES].connect(() => {
                update_spellcheck(context, config);
            });

        ClientWebView.default_context = context;
    }

    /**
     * Loads static resources used by ClientWebView.
     */
    public static void load_resources(GLib.File user_dir)
        throws GLib.Error {
        ClientWebView.script = load_app_script(
            "client-web-view.js"
        );
        ClientWebView.allow_remote_images = load_app_script(
            "client-web-view-allow-remote-images.js"
        );

        foreach (string name in new string[] { USER_CSS, USER_CSS_LEGACY }) {
            GLib.File stylesheet = user_dir.get_child(name);
            try {
                ClientWebView.user_stylesheet = load_user_stylesheet(stylesheet);
                break;
            } catch (GLib.IOError.NOT_FOUND err) {
                // All good, try the next one or just exit
            } catch (GLib.FileError.NOENT err) {
                // Ditto
            } catch (GLib.Error err) {
                warning(
                    "Could not load %s: %s", stylesheet.get_path(), err.message
                );
            }
        }
    }

    /** Loads an application-specific WebKit stylesheet. */
    protected static WebKit.UserStyleSheet load_app_stylesheet(string name)
        throws GLib.Error {
        return new WebKit.UserStyleSheet(
            GioUtil.read_resource(name),
            WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserStyleLevel.USER,
            null,
            null
        );
    }

    /** Loads a user stylesheet from disk. */
    protected static WebKit.UserStyleSheet? load_user_stylesheet(GLib.File name)
        throws GLib.Error {
        Geary.Memory.FileBuffer buf = new Geary.Memory.FileBuffer(name, true);
        return new WebKit.UserStyleSheet(
            buf.get_valid_utf8(),
            WebKit.UserContentInjectedFrames.ALL_FRAMES,
            WebKit.UserStyleLevel.USER,
            null,
            null
        );
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

    private static inline void update_spellcheck(WebKit.WebContext context,
                                                 Configuration config) {
        context.set_spell_checking_enabled(config.spell_check_languages.length > 0);
        context.set_spell_checking_languages(config.spell_check_languages);
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


    /** Delegate for UserContentManager message callbacks. */
    public delegate void JavaScriptMessageHandler(WebKit.JavascriptResult js_result);

    /**
     * Determines if the view's content has been fully loaded.
     *
     * This property is updated immediately before the {@link
     * content_loaded} signal is fired, and is triggered by the
     * PageState JavaScript object completing its load
     * handler. I.e. This will be true after the in-page JavaScript has
     * finished making any modifications to the page content.
     *
     * This will likely be fired after WebKitGTK sets the `is-loading`
     * property to `FALSE` and emits `load-changed` with
     * `WebKitLoadEvent.LOAD_FINISHED`, since they are related to
     * network resource loading, not page content.
     */
    public bool is_content_loaded { get; private set; default = false; }

    /** Determines if the view has any selected text */
    public bool has_selection { get; private set; default = false; }

    /** The HTML content's current preferred height in window pixels. */
    public int preferred_height {
        get {
            return (int) GLib.Math.round(
                this.webkit_reported_height * this.zoom_level
            );
        }
    }

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
    private string _document_font;

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
    private string _monospace_font;

    private weak string? body = null;

    private Gee.Map<string,Geary.Memory.Buffer> internal_resources =
        new Gee.HashMap<string,Geary.Memory.Buffer>();

    private Gee.List<ulong> registered_message_handlers =
        new Gee.LinkedList<ulong>();

    private double webkit_reported_height = 0;


    /**
     * Emitted when the view's content has finished loaded.
     *
     * See {@link is_content_loaded} for detail about when this is
     * emitted.
     */
    public signal void content_loaded();

    /** Emitted when the web view's undo/redo stack state changes. */
    public signal void command_stack_changed(bool can_undo, bool can_redo);

    /** Emitted when the web view's content has changed. */
    public signal void document_modified();

    /** Emitted when the view's selection has changed. */
    public signal void selection_changed(bool has_selection);

    /** Emitted when a user clicks a link in the view. */
    public signal void link_activated(string uri);

    /** Emitted when the view has loaded a resource added to it. */
    public signal void internal_resource_loaded(string name);

    /** Emitted when a remote image load was disallowed. */
    public signal void remote_image_load_blocked();


    protected ClientWebView(Configuration config,
                            WebKit.UserContentManager? custom_manager = null) {
        WebKit.Settings setts = new WebKit.Settings();
        setts.allow_modal_dialogs = false;
        setts.default_charset = "UTF-8";
        setts.enable_developer_extras = config.enable_inspector;
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
        if (ClientWebView.user_stylesheet != null) {
            content_manager.add_style_sheet(ClientWebView.user_stylesheet);
        }

        Object(
            web_context: ClientWebView.default_context,
            user_content_manager: content_manager,
            settings: setts
        );
        base_ref();

        // XXX get the allow prefix from the extension somehow

        this.decide_policy.connect(on_decide_policy);
        this.web_process_terminated.connect((reason) => {
                warning("Web process crashed: %s", reason.to_string());
            });

        register_message_handler(
            COMMAND_STACK_CHANGED, on_command_stack_changed
        );
        register_message_handler(
            CONTENT_LOADED, on_content_loaded
        );
        register_message_handler(
            DOCUMENT_MODIFIED, on_document_modified
        );
        register_message_handler(
            PREFERRED_HEIGHT_CHANGED, on_preferred_height_changed
        );
        register_message_handler(
            REMOTE_IMAGE_LOAD_BLOCKED, on_remote_image_load_blocked
        );
        register_message_handler(
            SELECTION_CHANGED, on_selection_changed
        );

        // Manage zoom level, ensure it's sane
        config.bind(Configuration.CONVERSATION_VIEWER_ZOOM_KEY, this, "zoom_level");
        if (this.zoom_level < ZOOM_MIN) {
            this.zoom_level = ZOOM_MIN;
        } else if (this.zoom_level > ZOOM_MAX) {
            this.zoom_level = ZOOM_MAX;
        }
        this.scroll_event.connect(on_scroll_event);

        // Watch desktop font settings
        Settings system_settings = config.gnome_interface;
        system_settings.bind("document-font-name", this,
                             "document-font", SettingsBindFlags.DEFAULT);
        system_settings.bind("monospace-font-name", this,
                             "monospace-font", SettingsBindFlags.DEFAULT);
    }

    ~ClientWebView() {
        base_unref();
    }

    public override void destroy() {
        foreach (ulong id in this.registered_message_handlers) {
            this.user_content_manager.disconnect(id);
        }
        this.registered_message_handlers.clear();
        base.destroy();
    }

    /**
     * Loads a message HTML body into the view.
     */
    public new void load_html(string? body, string? base_uri=null) {
        this.body = body;
        base.load_html(body, base_uri ?? INTERNAL_URL_BODY);
    }

    /**
     * Returns the view's content as an HTML string.
     */
    public async string? get_html() throws Error {
        return WebKitUtil.to_string(
            yield call(Geary.JS.callable("geary.getHtml"), null)
        );
    }

    /**
     * Adds an resource that may be accessed from the view via a URL.
     *
     * Internal resources may be access via both the internal `geary`
     * scheme (for resources such as an image inserted via the
     * composer) or via the `cid` scheme (for standard HTML email IMG
     * elements).
     */
    public void add_internal_resource(string id, Geary.Memory.Buffer buf) {
        this.internal_resources[id] = buf;
    }

    /**
     * Adds a set of internal resources to the view.
     *
     * @see add_internal_resource
     */
    public void add_internal_resources(Gee.Map<string,Geary.Memory.Buffer> res) {
        this.internal_resources.set_all(res);
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
        this.call.begin(Geary.JS.callable("geary.loadRemoteImages"), null);
    }

    /**
     * Selects all content in the web view.
     */
    public void select_all() {
        execute_editing_command(WebKit.EDITING_COMMAND_SELECT_ALL);
    }

    /**
     * Copies selected content and sends it to the clipboard.
     */
    public void copy_clipboard() {
        execute_editing_command(WebKit.EDITING_COMMAND_COPY);
    }

    public void zoom_reset() {
        this.zoom_level = ZOOM_DEFAULT;
        // Notify the preferred height has changed since it depends on
        // the zoom level. Same for zoom in and out below.
        notify_property("preferred-height");
    }

    public void zoom_in() {
        double new_zoom = this.zoom_level += (this.zoom_level * ZOOM_FACTOR);
        if (new_zoom > ZOOM_MAX) {
            new_zoom = ZOOM_MAX;
        }
        this.zoom_level = new_zoom;
        notify_property("preferred-height");
    }

    public void zoom_out() {
        double new_zoom = this.zoom_level -= (this.zoom_level * ZOOM_FACTOR);
        if (new_zoom < ZOOM_MIN) {
            new_zoom = ZOOM_MIN;
        }
        this.zoom_level = new_zoom;
        notify_property("preferred-height");
    }

    public new async void set_editable(bool enabled,
                                       Cancellable? cancellable)
        throws Error {
        yield call(
            Geary.JS.callable("geary.setEditable").bool(enabled), cancellable
        );
    }

    /**
     * Invokes a {@link Geary.JS.Callable} on this web view.
     */
    protected async WebKit.JavascriptResult call(Geary.JS.Callable target,
                                                 Cancellable? cancellable)
    throws Error {
        return yield run_javascript(target.to_string(), cancellable);
    }

    /**
     * Convenience function for registering and connecting JS messages.
     */
    protected inline void register_message_handler(string name,
                                                   JavaScriptMessageHandler handler) {
        // XXX can't use the delegate directly, see b.g.o Bug
        // 604781. However the workaround below creates a circular
        // reference, causing ClientWebView instances to leak. So to
        // work around that we need to record handler ids and
        // disconnect them when being destroyed.
        ulong id = this.user_content_manager.script_message_received[name].connect(
            (result) => { handler(result); }
        );
        this.registered_message_handlers.add(id);
        if (!this.user_content_manager.register_script_message_handler(name)) {
            debug("Failed to register script message handler: %s", name);
        }
    }

    private void handle_cid_request(WebKit.URISchemeRequest request) {
        if (!handle_internal_response(request)) {
            request.finish_error(new FileError.NOENT("Unknown CID"));
        }
    }

    private void handle_internal_request(WebKit.URISchemeRequest request) {
        if (request.get_uri() == INTERNAL_URL_BODY) {
            Geary.Memory.Buffer buf = new Geary.Memory.StringBuffer(this.body);
            request.finish(buf.get_input_stream(), buf.size, null);
        } else if (!handle_internal_response(request)) {
            request.finish_error(new FileError.NOENT("Unknown internal URL"));
        }
    }

    private bool handle_internal_response(WebKit.URISchemeRequest request) {
        string name = soup_uri_decode(request.get_path());
        Geary.Memory.Buffer? buf = this.internal_resources[name];
        bool handled = false;
        if (buf != null) {
            request.finish(buf.get_input_stream(), buf.size, null);
            internal_resource_loaded(name);
            handled = true;
        }
        return handled;
    }

    // This method is called only when determining if something should
    // be loaded for display in the web view as the primary
    // resource. It is not used to determine if sub-resources such as
    // images or JS will be loaded. So we only allow geary:body loads,
    // and notify but ignore if the user attempts to click on a link,
    // and deny everything else.
    private bool on_decide_policy(WebKit.WebView view,
                                  WebKit.PolicyDecision policy,
                                  WebKit.PolicyDecisionType type) {
        if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION ||
            type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
            WebKit.NavigationPolicyDecision nav_policy =
                (WebKit.NavigationPolicyDecision) policy;
            WebKit.NavigationAction nav_action =
                nav_policy.get_navigation_action();
            switch (nav_action.get_navigation_type()) {
            case WebKit.NavigationType.OTHER:
                if (nav_action.get_request().uri == INTERNAL_URL_BODY) {
                    policy.use();
                } else {
                    policy.ignore();
                }
                break;

            case WebKit.NavigationType.LINK_CLICKED:
                // Let the app know a user activated a link, but don't
                // try to load it ourselves.

                // We need to call ignore() before emitting the signal
                // to unblock the WebKit WebProcess, otherwise the
                // call chain for mailto links will cause the
                // WebProcess to deadlock, and the resulting composer
                // will be useless. See Geary Bug 771504
                // <https://bugzilla.gnome.org/show_bug.cgi?id=771504>
                // and WebKitGTK Bug 182528
                // <https://bugs.webkit.org/show_bug.cgi?id=182528>
                policy.ignore();
                link_activated(nav_action.get_request().uri);
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

    private void on_preferred_height_changed(WebKit.JavascriptResult result) {
        double height = this.webkit_reported_height;
        try {
            height = WebKitUtil.to_number(result);
        } catch (Geary.JS.Error err) {
            debug("Could not get preferred height: %s", err.message);
        }

        if (this.webkit_reported_height != height) {
            this.webkit_reported_height = height;
            notify_property("preferred-height");
        }
    }

    private void on_command_stack_changed(WebKit.JavascriptResult result) {
        try {
            string[] values = WebKitUtil.to_string(result).split(",");
            command_stack_changed(values[0] == "true", values[1] == "true");
        } catch (Geary.JS.Error err) {
            debug("Could not get command stack state: %s", err.message);
        }
    }

    private void on_document_modified(WebKit.JavascriptResult result) {
        document_modified();
    }

    private void on_remote_image_load_blocked(WebKit.JavascriptResult result) {
        remote_image_load_blocked();
    }

    private void on_content_loaded(WebKit.JavascriptResult result) {
        this.is_content_loaded = true;
        content_loaded();
    }

    private void on_selection_changed(WebKit.JavascriptResult result) {
        try {
            bool has_selection = WebKitUtil.to_bool(result);
            // Avoid firing multiple notifies if the value hasn't
            // changed
            if (this.has_selection != has_selection) {
                this.has_selection = has_selection;
            }
            selection_changed(has_selection);
        } catch (Geary.JS.Error err) {
            debug("Could not get selection content: %s", err.message);
        }
    }

}

// XXX this needs to be moved into the libsoup bindings
extern string soup_uri_decode(string part);
