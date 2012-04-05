/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Wrapper class for GSettings.
public class Configuration {
    public signal void display_preview_changed();
    public signal void spell_check_changed();
    
    private Settings settings;
    private Settings gnome_interface;
    private Settings? indicator_datetime;
    
    private const string WINDOW_WIDTH_NAME = "window-width";
    public int window_width {
        get { return settings.get_int(WINDOW_WIDTH_NAME); }
        set { settings.set_int(WINDOW_WIDTH_NAME, value); }
    }
    
    private const string WINDOW_HEIGHT_NAME = "window-height";
    public int window_height {
        get { return settings.get_int(WINDOW_HEIGHT_NAME); }
        set { settings.set_int(WINDOW_HEIGHT_NAME, value); }
    }
    
    private const string WINDOW_MAXIMIZE_NAME = "window-maximize";
    public bool window_maximize {
        get { return settings.get_boolean(WINDOW_MAXIMIZE_NAME); }
        set { settings.set_boolean(WINDOW_MAXIMIZE_NAME, value); }
    }
    
    private const string FOLDER_LIST_PANE_POSITION_NAME = "folder-list-pane-position";
    public int folder_list_pane_position {
        get { return settings.get_int(FOLDER_LIST_PANE_POSITION_NAME); }
        set { settings.set_int(FOLDER_LIST_PANE_POSITION_NAME, value); }
    }
    
    private const string MESSAGES_PANE_POSITION_NAME = "messages-pane-position";
    public int messages_pane_position {
        get { return settings.get_int(MESSAGES_PANE_POSITION_NAME); }
        set { settings.set_int(MESSAGES_PANE_POSITION_NAME, value); }
    }
    
    private const string AUTOSELECT_NAME = "autoselect";
    public bool autoselect {
        get { return settings.get_boolean(AUTOSELECT_NAME); }
        set { settings.set_boolean(AUTOSELECT_NAME, value); }
    }
    
    private const string DISPLAY_PREVIEW_NAME = "display-preview";
    public bool display_preview {
        get { return settings.get_boolean(DISPLAY_PREVIEW_NAME); }
        set {
            settings.set_boolean(DISPLAY_PREVIEW_NAME, value);
            display_preview_changed(); 
        }
    }
    
    private const string SPELL_CHECK_NAME = "spell-check";
    public bool spell_check {
        get { return settings.get_boolean(SPELL_CHECK_NAME); }
        set {
            settings.set_boolean(SPELL_CHECK_NAME, value);
            spell_check_changed();
        }
    }
    
    private const string CLOCK_FORMAT_NAME = "clock-format";
    private const string TIME_FORMAT_NAME = "time-format";
    public Date.ClockFormat clock_format {
        get {
            if (indicator_datetime != null) {
                string format = indicator_datetime.get_string(TIME_FORMAT_NAME);
                if (format == "12-hour")
                    return Date.ClockFormat.TWELVE_HOURS;
                else if (format == "24-hour")
                    return Date.ClockFormat.TWENTY_FOUR_HOURS;
                else {
                    // locale-default or custom
                    return Date.ClockFormat.LOCALE_DEFAULT;
                }
            }
            if (gnome_interface.get_string(CLOCK_FORMAT_NAME) == "12h")
                return Date.ClockFormat.TWELVE_HOURS;
            else
                return Date.ClockFormat.TWENTY_FOUR_HOURS;
        }
    }
    
    // Creates a configuration object.
    // is_installed: set to true if installed, else false.
    // schema_dir: MUST be set if not installed. Directory where GSettings schema is located.
    public Configuration(bool is_installed, string? schema_dir = null) {
        if (!is_installed) {
            assert(schema_dir != null);
            // If not installed, set an environment variable pointing to where the GSettings schema
            // is to be found.
            GLib.Environment.set_variable("GSETTINGS_SCHEMA_DIR", schema_dir, true);
        }
        
        // Start GSettings.
        settings = new Settings("org.yorba.geary");
        gnome_interface = new Settings("org.gnome.desktop.interface");
        foreach(string schema in GLib.Settings.list_schemas()) {
            if (schema == "com.canonical.indicator.datetime") {
                indicator_datetime = new Settings("com.canonical.indicator.datetime");
                break;
            }
        }
    }
}

