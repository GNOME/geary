/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2016-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Base class for all WebKit2 WebView instances used by the Geary client.
 *
 * This provides common functionality expected by the client for
 * displaying HTML, such as common WebKit settings, desktop font
 * integration, Inspector support, and remote and inline resource
 * handling for content such as images and videos.
 */
public abstract class Components.WebView : WebKit.WebView, Geary.BaseInterface {


    /** URI Scheme and delimiter for internal resource loads. */
    public const string INTERNAL_URL_PREFIX = "geary:";

    /** URI for internal message body page loads. */
    public const string INTERNAL_URL_BODY = INTERNAL_URL_PREFIX + "body";

    /** URI Scheme and delimiter for resources loaded by Content-ID. */
    public const string CID_URL_PREFIX = "cid:";

    // Keep these in sync with GearyWebExtension
    private const string MESSAGE_ENABLE_REMOTE_LOAD = "__enable_remote_load__";
    private const string MESSAGE_EXCEPTION = "__exception__";
    private const string MESSAGE_RETURN_VALUE = "__return__";

    // WebKit message handler names
    private const string COMMAND_STACK_CHANGED = "command_stack_changed";
    private const string CONTENT_LOADED = "content_loaded";
    private const string DOCUMENT_MODIFIED = "document_modified";
    private const string PREFERRED_HEIGHT_CHANGED = "preferred_height_changed";
    private const string REMOTE_RESOURCE_LOAD_BLOCKED = "remote_resource_load_blocked";
    private const string SELECTION_CHANGED = "selection_changed";

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

    private static List<WebKit.UserStyleSheet> styles = new List<WebKit.UserStyleSheet>();

    private static List<WebKit.UserScript> scripts = new List<WebKit.UserScript>();


    /**
     * Initialises WebKit.WebContext for use by the client.
     */
    public static void init_web_context(Application.Configuration config,
                                        File web_extension_dir,
                                        File cache_dir,
                                        bool sandboxed=true) {
        WebsiteDataManager data_manager = new WebsiteDataManager(cache_dir.get_path());
        WebKit.WebContext context = new WebKit.WebContext.with_website_data_manager(data_manager);
        // Enable WebProcess sandboxing
        if (sandboxed) {
            context.add_path_to_sandbox(web_extension_dir.get_path(), true);
            context.set_sandbox_enabled(true);
        }
        // Use the doc browser model so that we get some caching of
        // resources between email body loads.
        context.set_cache_model(WebKit.CacheModel.DOCUMENT_BROWSER);

        context.register_uri_scheme("cid", (req) => {
                WebView? view = req.get_web_view() as WebView;
                if (view != null) {
                    view.handle_cid_request(req);
                }
            });
        context.register_uri_scheme("geary", (req) => {
                WebView? view = req.get_web_view() as WebView;
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
        config.settings.changed[
            Application.Configuration.SPELL_CHECK_LANGUAGES
        ].connect(() => {
                update_spellcheck(context, config);
            });

        WebView.default_context = context;
    }

    /**
     * Loads static resources used by WebView.
     */
    public static void load_resources(GLib.File user_dir)
        throws GLib.Error {
        WebView.scripts.append(load_app_script("darkreader.js"));
        WebView.scripts.append(load_app_script("components-web-view.js"));
        WebView.styles.append(load_app_stylesheet("components-web-view.css"));

        foreach (string name in new string[] { USER_CSS, USER_CSS_LEGACY }) {
            GLib.File stylesheet = user_dir.get_child(name);
            try {
                WebView.styles.append(load_user_stylesheet(stylesheet));
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
                                                 Application.Configuration config) {
        string[] langs = config.get_spell_check_languages();
        context.set_spell_checking_enabled(langs.length > 0);
        context.set_spell_checking_languages(langs);
    }

    private static inline uint to_wk2_font_size(Pango.FontDescription font) {
        double size = font.get_size();
        if (!font.get_size_is_absolute()) {
            size = size / Pango.SCALE;
        }
        return (uint) WebKit.Settings.font_size_to_pixels((uint) size);
    }

    private static inline double get_text_scale () {
        return Gtk.Settings.get_default().gtk_xft_dpi / 96.0 / 1024.0;
    }

    /**
     * Delegate for message handler callbacks.
     *
     * @see register_message_callback
     */
    protected delegate void MessageCallback(GLib.Variant? parameters);

    // Work around for not being able to put delegates in a Gee collection.
    private class MessageCallable {

        public unowned MessageCallback handler;

        public MessageCallable(MessageCallback handler) {
            this.handler = handler;
        }

    }

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

    /**
     * Specifies whether loading remote resources is currently permitted.
     *
     * If false, any remote resources contained in HTML loaded into
     * the view will be blocked.
     *
     * @see load_remote_resources
     */
    public bool is_load_remote_resources_enabled {
        get; private set; default = false;
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

    private Gee.Map<string,MessageCallable> message_handlers =
        new Gee.HashMap<string,MessageCallable>();

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

    /** Emitted when a user clicks a link in the view. */
    public signal void link_activated(string uri);

    /** Emitted when the view has loaded a resource added to it. */
    public signal void internal_resource_loaded(string name);

    /** Emitted when a remote resource load was disallowed. */
    public signal void remote_resource_load_blocked();


    protected WebView(Application.Configuration config,
                      WebKit.UserContentManager? custom_manager = null,
                      WebView? related = null) {
        WebKit.Settings setts = new WebKit.Settings();
        setts.allow_modal_dialogs = false;
        setts.default_charset = "UTF-8";
        setts.enable_developer_extras = config.enable_inspector;
        setts.enable_fullscreen = false;
        setts.enable_html5_database = false;
        setts.enable_html5_local_storage = false;
        setts.enable_javascript = true;
        setts.enable_javascript_markup = false;
        setts.enable_media_stream = false;
        setts.enable_offline_web_application_cache = false;
        setts.enable_page_cache = false;
#if WEBKIT_PLUGINS_SUPPORTED
        setts.enable_plugins = false;
#endif
        setts.hardware_acceleration_policy =
            WebKit.HardwareAccelerationPolicy.NEVER;
        setts.javascript_can_access_clipboard = true;

        WebKit.UserContentManager content_manager =
             custom_manager ?? new WebKit.UserContentManager();

        if (config.unset_html_colors) {
            WebView.scripts.append(
                new WebKit.UserScript(
                    "window.UNSET_HTML_COLORS = true;",
                    WebKit.UserContentInjectedFrames.TOP_FRAME,
                    WebKit.UserScriptInjectionTime.START,
                    null,
                    null
                )
            );
        }

        WebView.scripts.foreach(script => content_manager.add_script(script));
        WebView.styles.foreach(style => content_manager.add_style_sheet(style));

        Object(
            settings: setts,
            user_content_manager: content_manager,
            web_context: WebView.default_context
        );
        base_ref();
        init(config);
    }

    /**
     * Constructs a new web view with a new shared WebProcess.
     *
     * The new view will use the same WebProcess, settings and content
     * manager as the given related view's.
     *
     * @see WebKit.WebView.WebView.with_related_view
     */
    protected WebView.with_related_view(Application.Configuration config,
                                        WebView related) {
        Object(
            related_view: related,
            settings: related.get_settings(),
            user_content_manager: related.user_content_manager
        );
        base_ref();
        init(config);
    }

    ~WebView() {
        base_unref();
    }

    public override void destroy() {
        this.message_handlers.clear();
        base.destroy();
    }

    /**
     * Loads a message HTML body into the view.
     */
    public new void load_html(string? body, string? base_uri=null) {
        this.body = body;
        // The viewport width will be 0 if the email is loaded before
        // its WebView is laid out in the widget hierarchy. As a workaround, to
        // prevent this causing the email being squished down to is minimum
        // width and hence being stretched right out in height, always load
        // HTML once view is mapped
        if (this.get_mapped()) {
            base.load_html(body, base_uri ?? INTERNAL_URL_BODY);
        } else {
            ulong handler_id = 0;
            handler_id = this.map.connect(() => {
                base.load_html(body, base_uri ?? INTERNAL_URL_BODY);
                if (handler_id > 0) {
                    this.disconnect(handler_id);
                }
            });
        }
    }

    /**
     * Loads a message HTML body into the view.
     */
    public new void load_html_headless(string? body, string? base_uri=null) {
        this.body = body;
        base.load_html(body, base_uri ?? INTERNAL_URL_BODY);
    }

    /**
     * Returns the view's content as an HTML string.
     */
    public async string? get_html() throws Error {
        return yield call_returning<string?>(Util.JS.callable("getHtml"), null);
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
     * Load any remote resources that were previously blocked.
     *
     * Calling this before calling {@link load_html} will enable any
     * remote resources to be loaded as the HTML is loaded. Calling it
     * afterwards wil ensure any remote resources that were blocked
     * during initial HTML page load are now loaded.
     *
     * @see is_load_remote_resources_enabled
     */
    public async void load_remote_resources(GLib.Cancellable? cancellable)
        throws GLib.Error {
        this.is_load_remote_resources_enabled = true;
        yield this.call_void(
            Util.JS.callable(MESSAGE_ENABLE_REMOTE_LOAD), null
        );
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
        yield call_void(
            Util.JS.callable("setEditable").bool(enabled), cancellable
        );
    }

    /**
     * Invokes a {@link Util.JS.Callable} on this web view.
     *
     * This calls the given callable on the `geary` object for the
     * current view, any returned value are ignored.
     */
    protected async void call_void(Util.JS.Callable target,
                                   GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield call_impl(target, cancellable);
    }

    /**
     * Invokes a {@link Util.JS.Callable} on this web view.
     *
     * This calls the given callable on the `geary` object for the
     * current view. The value returned by the call is returned by
     * this method.
     *
     * The type parameter `T` must match the type returned by the
     * call, else an error is thrown. Only simple nullable value types
     * are supported for T, for more complex return types (arrays,
     * dictionaries, etc) specify {@link GLib.Variant} for `T` and
     * manually parse that.
     */
    protected async T call_returning<T>(Util.JS.Callable target,
                                        GLib.Cancellable? cancellable)
        throws GLib.Error {
        WebKit.UserMessage? response = yield call_impl(target, cancellable);
        if (response == null) {
            throw new Util.JS.Error.TYPE(
                "Method call %s did not return a value", target.to_string()
            );
        }
        GLib.Variant? param = response.parameters;
        T ret_value = null;
        var ret_type = typeof(T);
        if (ret_type == typeof(GLib.Variant)) {
            ret_value = param;
        } else {
            if (param != null && param.get_type().is_maybe()) {
                param = param.get_maybe();
            }
            if (param != null) {
                // Since these replies are coming from JS via
                // Util.JS.value_to_variant, they will only be one of
                // string, double, bool, array or dict
                var param_type = param.classify();
                if (ret_type == typeof(string) && param_type == STRING) {
                    ret_value = param.get_string();
                } else if (ret_type == typeof(bool) && param_type == BOOLEAN) {
                    ret_value = (bool?) param.get_boolean();
                } else if (ret_type == typeof(int) && param_type == DOUBLE) {
                    ret_value = (int?) ((int) param.get_double());
                } else if (ret_type == typeof(short) && param_type == DOUBLE) {
                    ret_value = (short?) ((short) param.get_double());
                } else if (ret_type == typeof(char) && param_type == DOUBLE) {
                    ret_value = (char?) ((char) param.get_double());
                } else if (ret_type == typeof(long) && param_type == DOUBLE) {
                    ret_value = (long?) ((long) param.get_double());
                } else if (ret_type == typeof(int64) && param_type == DOUBLE) {
                    ret_value = (int64?) ((int64) param.get_double());
                } else if (ret_type == typeof(uint) && param_type == DOUBLE) {
                    ret_value = (uint?) ((uint) param.get_double());
                } else if (ret_type == typeof(uchar) && param_type == DOUBLE) {
                    ret_value = (uchar?) ((uchar) param.get_double());
                } else if (ret_type == typeof(ushort) && param_type == DOUBLE) {
                    ret_value = (ushort?) ((ushort) param.get_double());
                } else if (ret_type == typeof(ulong) && param_type == DOUBLE) {
                    ret_value = (ulong?) ((ulong) param.get_double());
                } else if (ret_type == typeof(uint64) && param_type == DOUBLE) {
                    ret_value = (uint64?) ((uint64) param.get_double());
                } else if (ret_type == typeof(double) && param_type == DOUBLE) {
                    ret_value = (double?) param.get_double();
                } else if (ret_type == typeof(float) && param_type == DOUBLE) {
                    ret_value = (float?) ((float) param.get_double());
                } else {
                    throw new Util.JS.Error.TYPE(
                        "%s is not a supported type for %s",
                        ret_type.name(), param_type.to_string()
                    );
                }
            }
        }
        return ret_value;
    }

    /**
     * Registers a callback for a specific WebKit user message.
     */
    protected void register_message_callback(string name,
                                             MessageCallback handler) {
        this.message_handlers.set(name, new MessageCallable(handler));
    }

    private void init(Application.Configuration config) {
        // XXX get the allow prefix from the extension somehow

        this.decide_policy.connect(on_decide_policy);
        this.web_process_terminated.connect((reason) => {
                warning("Web process crashed: %s", reason.to_string());
            });

        register_message_callback(
            COMMAND_STACK_CHANGED, on_command_stack_changed
        );
        register_message_callback(
            CONTENT_LOADED, on_content_loaded
        );
        register_message_callback(
            DOCUMENT_MODIFIED, on_document_modified
        );
        register_message_callback(
            PREFERRED_HEIGHT_CHANGED, on_preferred_height_changed
        );
        register_message_callback(
            REMOTE_RESOURCE_LOAD_BLOCKED, on_remote_resource_load_blocked
        );
        register_message_callback(
            SELECTION_CHANGED, on_selection_changed
        );

        this.user_message_received.connect(this.on_message_received);

        // Manage zoom level, ensure it's sane
        config.bind(Application.Configuration.CONVERSATION_VIEWER_ZOOM_KEY, this, "zoom_level");
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

    private async WebKit.UserMessage? call_impl(Util.JS.Callable target,
                                                GLib.Cancellable? cancellable)
        throws GLib.Error {
        WebKit.UserMessage? response = yield send_message_to_page(
            target.to_message(), cancellable
        );
        if (response != null) {
            var response_name = response.name;
            if (response_name == MESSAGE_EXCEPTION) {
                var exception = new GLib.VariantDict(response.parameters);
                var name = exception.lookup_value("name", GLib.VariantType.STRING) as string;
                var message = exception.lookup_value("message", GLib.VariantType.STRING) as string;
                var backtrace = exception.lookup_value("backtrace_string", GLib.VariantType.STRING) as string;
                var source = exception.lookup_value("source_uri", GLib.VariantType.STRING) as string;
                var line = exception.lookup_value("line_number", GLib.VariantType.UINT32);
                var column = exception.lookup_value("column_number", GLib.VariantType.UINT32);

                var log_message = "Method call %s raised %s exception at %s:%d:%d: %s".printf(
                    target.to_string(),
                    name ?? "unknown",
                    source ?? "unknown",
                    (line != null ? (int) line.get_uint32() : -1),
                    (column != null ? (int) column.get_uint32() : -1),
                    message ?? "unknown"
                );
                debug(log_message);
                if (backtrace != null) {
                    debug(backtrace);
                }

                throw new Util.JS.Error.EXCEPTION(log_message);
            } else if (response_name != MESSAGE_RETURN_VALUE) {
                throw new Util.JS.Error.TYPE(
                    "Method call %s returned unknown name: %s",
                    target.to_string(),
                    response_name
                );
            }
        }
        return response;
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
        string name = GLib.Uri.unescape_string(request.get_path());
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

    private void on_preferred_height_changed(GLib.Variant? parameters) {
        double height = this.webkit_reported_height;
        if (parameters != null && parameters.classify() == DOUBLE) {
            // WebkitGtk (after 2.45.3) returns height without taking into account font scaling,
            // Multiply by `get_text_scale()` to fix the issue.
            // Related commit: https://github.com/WebKit/WebKit/commit/5713584438d253c13cb10966d7bac9cef1f9082f
            height = parameters.get_double() * get_text_scale();
        } else {
            warning("Could not get JS preferred height");
        }

        if (this.webkit_reported_height != height) {
            this.webkit_reported_height = height;
            notify_property("preferred-height");
        }
    }

    private void on_command_stack_changed(GLib.Variant? parameters) {
        if (parameters != null &&
            parameters.is_container() &&
            parameters.n_children() == 2) {
            GLib.Variant can_undo = parameters.get_child_value(0);
            GLib.Variant can_redo = parameters.get_child_value(1);
            command_stack_changed(
                can_undo.classify() == BOOLEAN && can_undo.get_boolean(),
                can_redo.classify() == BOOLEAN && can_redo.get_boolean()
            );
        } else {
            warning("Could not get JS command stack state");
        }
    }

    private void on_document_modified(GLib.Variant? parameters) {
        document_modified();
    }

    private void on_remote_resource_load_blocked(GLib.Variant? parameters) {
        remote_resource_load_blocked();
    }

    private void on_content_loaded(GLib.Variant? parameters) {
        this.is_content_loaded = true;
        content_loaded();
    }

    private void on_selection_changed(GLib.Variant? parameters) {
        if (parameters != null && parameters.classify() == BOOLEAN) {
            this.has_selection = parameters.get_boolean();
        } else {
            warning("Could not get JS selection value");
        }
    }

    private bool on_message_received(WebKit.UserMessage message) {
        if (message.name == MESSAGE_EXCEPTION) {
            var detail = new GLib.VariantDict(message.parameters);
            var name = detail.lookup_value("name", GLib.VariantType.STRING) as string;
            var log_message = detail.lookup_value("message", GLib.VariantType.STRING) as string;
            warning(
                "Error sending message from JS: %s: %s",
                name ?? "unknown",
                log_message ?? "unknown"
            );
        } else if (this.message_handlers.has_key(message.name)) {
            debug(
                "Message received: %s(%s)",
                message.name,
                message.parameters != null ? message.parameters.print(true) : ""
            );
            MessageCallable callback = this.message_handlers.get(message.name);
            callback.handler(message.parameters);
        } else {
            warning("Message with unknown handler received: %s", message.name);
        }
        return true;
    }

}
