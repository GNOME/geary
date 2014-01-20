/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Singleton class to hold icons.
public class IconFactory {
    public const Gtk.IconSize ICON_TOOLBAR = Gtk.IconSize.LARGE_TOOLBAR;
    public const Gtk.IconSize ICON_SIDEBAR = Gtk.IconSize.MENU;
    
    private static IconFactory? _instance = null;
    public static IconFactory instance {
        get {
            if (_instance == null)
                _instance = new IconFactory();
            
            return _instance;
        }
        
        private set { _instance = value; }
    }
    
    public const int APPLICATION_ICON_SIZE = 128;
    public Gdk.Pixbuf application_icon { get; private set; }
    
    public const int UNREAD_ICON_SIZE = 16;
    public Gdk.Pixbuf unread { get; private set; }
    public Gdk.Pixbuf read { get; private set; }
    public Gdk.Pixbuf unread_colored { get; private set; }
    public Gdk.Pixbuf read_colored { get; private set; }
    
    public const int STAR_ICON_SIZE = 16;
    public Gdk.Pixbuf starred { get; private set; }
    public Gdk.Pixbuf unstarred { get; private set; }
    public Gdk.Pixbuf starred_colored { get; private set; }
    public Gdk.Pixbuf unstarred_colored { get; private set; }
    
    private Gtk.IconTheme icon_theme { get; private set; }
    
    private File icons_dir;
    
    // Creates the icon factory.
    private IconFactory() {
        icon_theme = Gtk.IconTheme.get_default();
        icons_dir = GearyApplication.instance.get_resource_directory().get_child("icons");
        
        append_icons_search_path(null);
        append_icons_search_path("128x128");
        append_icons_search_path("48x48");
        append_icons_search_path("24x24");
        append_icons_search_path("16x16");
        
        // Load icons here.
        application_icon = load("geary", APPLICATION_ICON_SIZE);
        unread = load("unread-symbolic", UNREAD_ICON_SIZE);
        read = load("read-symbolic", UNREAD_ICON_SIZE);
        starred = load("star-symbolic", STAR_ICON_SIZE);
        unstarred = load("unstarred-symbolic", STAR_ICON_SIZE);
        
        Gdk.RGBA gray_color = Gdk.RGBA();
        gray_color.parse(CountBadge.UNREAD_BG_COLOR);
        
        // Load pre-colored symbolic icons here.
        read_colored = load_symbolic_colored("read-symbolic", UNREAD_ICON_SIZE, gray_color);
        unread_colored = load_symbolic_colored("unread-symbolic", STAR_ICON_SIZE, gray_color);
        starred_colored = load_symbolic_colored("star-symbolic", STAR_ICON_SIZE, gray_color);
        unstarred_colored = load_symbolic_colored("unstarred-symbolic", STAR_ICON_SIZE, gray_color);
    }
    
    public void init() {
        // perform any additional initialization here; at this time, everything is done in the
        // constructor
    }
    
    private int icon_size_to_pixels(Gtk.IconSize icon_size) {
        switch (icon_size) {
            case ICON_SIDEBAR:
                return 16;
            
            case ICON_TOOLBAR:
            default:
                return 24;
        }
    }
    
    public Icon get_theme_icon(string name) {
        return new ThemedIcon(name);
    }
    
    public Icon get_custom_icon(string name, Gtk.IconSize size) {
        int pixels = icon_size_to_pixels(size);
        
        // Try sized icon first.
        File icon_file = icons_dir.get_child("%dx%d".printf(pixels, pixels)).get_child(
            "%s.svg".printf(name));
        
        // If that wasn't found, try a non-sized icon.
        if (!icon_file.query_exists())
            icon_file = icons_dir.get_child("%s.svg".printf(name));
        
        return new FileIcon(icon_file);
    }
    
    private void append_icons_search_path(string? name) {
        if (Geary.String.is_empty(name))
            icon_theme.append_search_path(icons_dir.get_path());
        else
            icon_theme.append_search_path(icons_dir.get_child(name).get_path());
    }
    
    private Gdk.Pixbuf? load(string icon_name, int size, Gtk.IconLookupFlags flags = 0) {
        // Try looking up IconInfo (to report path in case of error) then load image
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        if (icon_info != null) {
            try {
                return icon_info.load_icon();
            } catch (Error err) {
                warning("Couldn't load icon %s at %s, falling back to image-missing: %s", icon_name,
                    icon_info.get_filename(), err.message);
            }
        } else {
            debug("Unable to lookup icon %s, falling back to image-missing...", icon_name);
        }
        
        // Default: missing image icon.
        return get_missing_icon(size, flags);
    }
    
    // Attempts to load and return the missing image icon.
    private Gdk.Pixbuf? get_missing_icon(int size, Gtk.IconLookupFlags flags = 0) {
        try {
            return icon_theme.load_icon("image-missing", size, flags);
        } catch (Error err) {
            warning("Couldn't load image-missing icon: %s", err.message);
        }
        
        // If that fails... well they're out of luck.
        return null;
    }
    
    public Gtk.IconInfo? lookup_icon(string icon_name, int size, Gtk.IconLookupFlags flags = 0) {
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        return icon_info != null ? icon_info.copy() :
            icon_theme.lookup_icon("document-symbolic", size, flags);
    }
    
    /**
     * Loads a symbolic icon into a pixbuf, where the color-key has been switched to the provided
     * color, or black if no color is set.
     */
    public Gdk.Pixbuf? load_symbolic_colored(string icon_name, int size, Gdk.RGBA? color = null,
        Gtk.IconLookupFlags flags = 0) {
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        
        // Default to black if no color provided.
        if (color == null) {
            color = Gdk.RGBA();
            color.red = color.green = color.blue = 0.0;
            color.alpha = 1.0;
        }
        
        // Attempt to load as a symbolic icon.
        if (icon_info != null) {
            try {
                return icon_info.load_symbolic(color);
            } catch (Error e) {
                warning("Couldn't load icon: %s", e.message);
            }
        }
        
        // Default: missing image icon.
        return get_missing_icon(size, flags);
    }
    
    public Gdk.Pixbuf? load_symbolic(string icon_name, int size, Gtk.StyleContext style,
        Gtk.IconLookupFlags flags = 0) {
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        
        // Attempt to load as a symbolic icon.
        if (icon_info != null) {
            try {
                return icon_info.load_symbolic_for_context(style);
            } catch (Error e) {
                message("Couldn't load icon: %s", e.message);
            }
        }
        
        // Default: missing image icon.
        return get_missing_icon(size, flags);
    }
}

