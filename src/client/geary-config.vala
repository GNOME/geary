/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Wrapper class for GSettings.
public class Configuration {
    private Settings settings;
    
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
    }
}

