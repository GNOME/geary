/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Provides convenience properties to current Geary GSettings values.
 */
public class Application.Configuration {


    public const string ASK_OPEN_ATTACHMENT_KEY = "ask-open-attachment";
    public const string AUTOSELECT_KEY = "autoselect";
    public const string COMPOSER_WINDOW_SIZE_KEY = "composer-window-size";
    public const string COMPOSE_AS_HTML_KEY = "compose-as-html";
    public const string CONVERSATION_VIEWER_ZOOM_KEY = "conversation-viewer-zoom";
    public const string DISPLAY_PREVIEW_KEY = "display-preview";
    public const string FOLDER_LIST_PANE_HORIZONTAL_KEY = "folder-list-pane-horizontal";
    public const string FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY = "folder-list-pane-position-horizontal";
    public const string FOLDER_LIST_PANE_POSITION_KEY = "folder-list-pane-position";
    public const string FOLDER_LIST_PANE_POSITION_VERTICAL_KEY = "folder-list-pane-position-vertical";
    public const string MESSAGES_PANE_POSITION_KEY = "messages-pane-position";
    public const string SEARCH_STRATEGY_KEY = "search-strategy";
    public const string SPELL_CHECK_LANGUAGES = "spell-check-languages";
    public const string SPELL_CHECK_VISIBLE_LANGUAGES = "spell-check-visible-languages";
    public const string STARTUP_NOTIFICATIONS_KEY = "startup-notifications";
    public const string WINDOW_HEIGHT_KEY = "window-height";
    public const string WINDOW_MAXIMIZE_KEY = "window-maximize";
    public const string WINDOW_WIDTH_KEY = "window-width";


    public enum DesktopEnvironment {
        UNKNOWN = 0,
        UNITY;
    }


    // is_installed: set to true if installed, else false.
    // schema_dir: MUST be set if not installed. Directory where GSettings schema is located.
    public static void init(bool is_installed, string? schema_dir = null) {
        if (!is_installed) {
            assert(schema_dir != null);
            // If not installed, set an environment variable pointing to where the GSettings schema
            // is to be found.
            GLib.Environment.set_variable("GSETTINGS_SCHEMA_DIR", schema_dir, true);
        }
    }


    public Settings settings { get; private set; }
    public Settings gnome_interface { get; private set; }

    // Can be set as an arguments
    public bool enable_debug { get; set; default = false; }

    // Can be set as an arguments
    public bool enable_inspector { get; set; default = false; }

    // Can be set as an arguments
    public bool revoke_certs { get; set; default = false; }

    public DesktopEnvironment desktop_environment {
        get {
            string? xdg_current_desktop = Environment.get_variable("XDG_CURRENT_DESKTOP");
            if (xdg_current_desktop != null && xdg_current_desktop.has_prefix("Unity")) {
                return DesktopEnvironment.UNITY;
            } else {
                return DesktopEnvironment.UNKNOWN;
            }
        }
    }

    public int window_width {
        get { return settings.get_int(WINDOW_WIDTH_KEY); }
    }

    public int window_height {
        get { return settings.get_int(WINDOW_HEIGHT_KEY); }
    }

    public bool window_maximize {
        get { return settings.get_boolean(WINDOW_MAXIMIZE_KEY); }
    }

    public int folder_list_pane_position_old {
        get { return settings.get_int(FOLDER_LIST_PANE_POSITION_KEY); }
    }

    public int folder_list_pane_position_horizontal {
        get { return settings.get_int(FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY); }
        set { settings.set_int(FOLDER_LIST_PANE_POSITION_HORIZONTAL_KEY, value); }
    }

    public int folder_list_pane_position_vertical {
        get { return settings.get_int(FOLDER_LIST_PANE_POSITION_VERTICAL_KEY); }
    }

    public bool folder_list_pane_horizontal {
        get { return settings.get_boolean(FOLDER_LIST_PANE_HORIZONTAL_KEY); }
    }

    public int messages_pane_position {
        get { return settings.get_int(MESSAGES_PANE_POSITION_KEY); }
        set { settings.set_int(MESSAGES_PANE_POSITION_KEY, value); }
    }

    public bool autoselect {
        get { return settings.get_boolean(AUTOSELECT_KEY); }
    }

    public bool display_preview {
        get { return settings.get_boolean(DISPLAY_PREVIEW_KEY); }
    }

    /**
     * The set of enabled spell checker languages.
     *
     * This specifies the languages used for spell checking by the
     * client. By default, the set will contain languages based on
     * environment variables.
     *
     * @see Util.International.get_user_preferred_languages
     */
    public string[] spell_check_languages {
        owned get {
            GLib.Variant? value =
                settings.get_value(SPELL_CHECK_LANGUAGES).get_maybe();
            string[] langs = (value != null)
                    ? value.get_strv()
                    : Util.International.get_user_preferred_languages();
            return langs;
        }
        set {
            settings.set_value(
                SPELL_CHECK_LANGUAGES,
                new GLib.Variant.maybe(null, new GLib.Variant.strv(value))
            );
        }
    }

    /**
     * The set of visible spell checker languages.
     *
     * This is the list of languages shown when selecting languages to
     * be used for spell checking.
     */
    public string[] spell_check_visible_languages {
        owned get {
            return settings.get_strv(SPELL_CHECK_VISIBLE_LANGUAGES);
        }
        set {
            settings.set_strv(SPELL_CHECK_VISIBLE_LANGUAGES, value);
        }
    }

    public bool startup_notifications {
        get { return settings.get_boolean(STARTUP_NOTIFICATIONS_KEY); }
        set { set_boolean(STARTUP_NOTIFICATIONS_KEY, value); }
    }

    private const string CLOCK_FORMAT_KEY = "clock-format";
    public Util.Date.ClockFormat clock_format {
        get {
            if (gnome_interface.get_string(CLOCK_FORMAT_KEY) == "12h")
                return Util.Date.ClockFormat.TWELVE_HOURS;
            else
                return Util.Date.ClockFormat.TWENTY_FOUR_HOURS;
        }
    }

    public bool ask_open_attachment {
        get { return settings.get_boolean(ASK_OPEN_ATTACHMENT_KEY); }
        set { set_boolean(ASK_OPEN_ATTACHMENT_KEY, value); }
    }

    public bool compose_as_html {
        get { return settings.get_boolean(COMPOSE_AS_HTML_KEY); }
        set { set_boolean(COMPOSE_AS_HTML_KEY, value); }
    }

    public double conversation_viewer_zoom {
        get { return settings.get_double(CONVERSATION_VIEWER_ZOOM_KEY); }
        set { settings.set_double(CONVERSATION_VIEWER_ZOOM_KEY, value); }
    }

    public int[] composer_window_size {
        owned get {
            int[] size = new int[2];
            var s = settings.get_value(COMPOSER_WINDOW_SIZE_KEY);
            if (s.n_children () == 2) {
                size = { (int) s.get_child_value(0), (int) s.get_child_value(1)};
            } else {
                size = {-1,-1};
            }
            return size;
        }
        set {
            settings.set_value(COMPOSER_WINDOW_SIZE_KEY, value);
        }
    }

    // Creates a configuration object.
    public Configuration(string schema_id) {
        // Start GSettings.
        settings = new Settings(schema_id);
        gnome_interface = new Settings("org.gnome.desktop.interface");

        Migrate.old_app_config(settings);
    }

    public void bind(string key, Object object, string property,
        SettingsBindFlags flags = GLib.SettingsBindFlags.DEFAULT) {
        settings.bind(key, object, property, flags);
    }

    private void set_boolean(string name, bool value) {
        if (!settings.set_boolean(name, value))
            message("Unable to set configuration value %s = %s", name, value.to_string());
    }

    public Geary.SearchQuery.Strategy get_search_strategy() {
        switch (settings.get_string(SEARCH_STRATEGY_KEY).down()) {
            case "exact":
                return Geary.SearchQuery.Strategy.EXACT;

            case "aggressive":
                return Geary.SearchQuery.Strategy.AGGRESSIVE;

            case "horizon":
                return Geary.SearchQuery.Strategy.HORIZON;

            case "conservative":
            default:
                return Geary.SearchQuery.Strategy.CONSERVATIVE;
        }
    }

    public void set_search_strategy(Geary.SearchQuery.Strategy strategy) {
        switch (strategy) {
            case Geary.SearchQuery.Strategy.EXACT:
                settings.set_string(SEARCH_STRATEGY_KEY, "exact");
            break;

            case Geary.SearchQuery.Strategy.AGGRESSIVE:
                settings.set_string(SEARCH_STRATEGY_KEY, "aggressive");
            break;

            case Geary.SearchQuery.Strategy.HORIZON:
                settings.set_string(SEARCH_STRATEGY_KEY, "horizon");
            break;

            case Geary.SearchQuery.Strategy.CONSERVATIVE:
            default:
                settings.set_string(SEARCH_STRATEGY_KEY, "conservative");
            break;
        }
    }
}

