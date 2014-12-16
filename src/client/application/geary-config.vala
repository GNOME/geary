/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Wrapper class for GSettings.
public class Configuration {
    public const string WINDOW_WIDTH_KEY = "window-width";
    public const string WINDOW_HEIGHT_KEY = "window-height";
    public const string WINDOW_MAXIMIZE_KEY = "window-maximize";
    public const string FOLDER_LIST_PANE_POSITION_KEY = "folder-list-pane-position";
    public const string MESSAGES_PANE_POSITION_KEY = "messages-pane-position";
    public const string AUTOSELECT_KEY = "autoselect";
    public const string DISPLAY_PREVIEW_KEY = "display-preview";
    public const string SPELL_CHECK_KEY = "spell-check";
    public const string PLAY_SOUNDS_KEY = "play-sounds";
    public const string SHOW_NOTIFICATIONS_KEY = "show-notifications";
    public const string STARTUP_NOTIFICATIONS_KEY = "startup-notifications";
    public const string ASK_OPEN_ATTACHMENT_KEY = "ask-open-attachment";
    public const string COMPOSE_AS_HTML_KEY = "compose-as-html";
    
    public Settings settings { get; private set; }
    
    public Settings gnome_interface;
    private Settings? indicator_datetime;
    
    public int window_width {
        get { return settings.get_int(WINDOW_WIDTH_KEY); }
    }
    
    public int window_height {
        get { return settings.get_int(WINDOW_HEIGHT_KEY); }
    }
    
    public bool window_maximize {
        get { return settings.get_boolean(WINDOW_MAXIMIZE_KEY); }
    }
    
    public int folder_list_pane_position {
        get { return settings.get_int(FOLDER_LIST_PANE_POSITION_KEY); }
    }
    
    public int messages_pane_position {
        get { return settings.get_int(MESSAGES_PANE_POSITION_KEY); }
    }
    
    public bool autoselect {
        get { return settings.get_boolean(AUTOSELECT_KEY); }
    }
    
    public bool display_preview {
        get { return settings.get_boolean(DISPLAY_PREVIEW_KEY); }
    }
    
    public bool spell_check {
        get { return settings.get_boolean(SPELL_CHECK_KEY); }
    }

    public bool play_sounds {
        get { return settings.get_boolean(PLAY_SOUNDS_KEY); }
    }

    public bool show_notifications {
        get { return settings.get_boolean(SHOW_NOTIFICATIONS_KEY); }
    }

    public bool startup_notifications {
        get { return settings.get_boolean(STARTUP_NOTIFICATIONS_KEY); }
        set { set_boolean(STARTUP_NOTIFICATIONS_KEY, value); }
    }
    
    private const string CLOCK_FORMAT_KEY = "clock-format";
    private const string TIME_FORMAT_KEY = "time-format";
    public Date.ClockFormat clock_format {
        get {
            if (indicator_datetime != null) {
                string format = indicator_datetime.get_string(TIME_FORMAT_KEY);
                if (format == "12-hour")
                    return Date.ClockFormat.TWELVE_HOURS;
                else if (format == "24-hour")
                    return Date.ClockFormat.TWENTY_FOUR_HOURS;
                else {
                    // locale-default or custom
                    return Date.ClockFormat.LOCALE_DEFAULT;
                }
            }
            if (gnome_interface.get_string(CLOCK_FORMAT_KEY) == "12h")
                return Date.ClockFormat.TWELVE_HOURS;
            else
                return Date.ClockFormat.TWENTY_FOUR_HOURS;
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
    
    // Creates a configuration object.
    public Configuration(string schema_id) {
        // Start GSettings.
        settings = new Settings(schema_id);
        gnome_interface = new Settings("org.gnome.desktop.interface");
        foreach(unowned string schema in GLib.Settings.list_schemas()) {
            if (schema == "com.canonical.indicator.datetime") {
                indicator_datetime = new Settings("com.canonical.indicator.datetime");
                break;
            }
        }
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
    
    public void bind(string key, Object object, string property,
        SettingsBindFlags flags = SettingsBindFlags.DEFAULT) {
        settings.bind(key, object, property, flags);
    }
    
    private void set_boolean(string name, bool value) {
        if (!settings.set_boolean(name, value))
            message("Unable to set configuration value %s = %s", name, value.to_string());
    }
    
    public Geary.SearchQuery.Strategy get_search_strategy() {
        switch (settings.get_string("search-strategy").down()) {
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
                settings.set_string("search-strategy", "exact");
            break;
            
            case Geary.SearchQuery.Strategy.AGGRESSIVE:
                settings.set_string("search-strategy", "aggressive");
            break;
            
            case Geary.SearchQuery.Strategy.HORIZON:
                settings.set_string("search-strategy", "horizon");
            break;
            
            case Geary.SearchQuery.Strategy.CONSERVATIVE:
            default:
                settings.set_string("search-strategy", "conservative");
            break;
        }
    }
}

