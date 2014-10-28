/* Copyright 2011-2014 Yorba Foundation
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
    public const int STAR_ICON_SIZE = 16;
    
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
            icon_theme.lookup_icon("text-x-generic-symbolic", size, flags);
    }
    
    // GTK+ 3.14 no longer scales icons via the IconInfo, so perform manually until we
    // properly install the icons as per 3.14's expectations.
    private Gdk.Pixbuf aspect_scale_down_pixbuf(Gdk.Pixbuf pixbuf, int size) {
        if (pixbuf.width <= size && pixbuf.height <= size)
            return pixbuf;
        
        int scaled_width, scaled_height;
        if (pixbuf.width >= pixbuf.height) {
            double aspect = (double) size / (double) pixbuf.width;
            scaled_width = size;
            scaled_height = (int) Math.round((double) pixbuf.height * aspect);
        } else {
            double aspect = (double) size / (double) pixbuf.height;
            scaled_width = (int) Math.round((double) pixbuf.width * aspect);
            scaled_height = size;
        }
        
        return pixbuf.scale_simple(scaled_width, scaled_height, Gdk.InterpType.BILINEAR);
    }
    
    public Gdk.Pixbuf? load_symbolic(string icon_name, int size, Gtk.StyleContext style,
        Gtk.IconLookupFlags flags = 0) {
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        
        // Attempt to load as a symbolic icon.
        if (icon_info != null) {
            try {
                return aspect_scale_down_pixbuf(icon_info.load_symbolic_for_context(style), size);
            } catch (Error e) {
                message("Couldn't load icon: %s", e.message);
            }
        }
        
        // Default: missing image icon.
        return get_missing_icon(size, flags);
    }
    
    /**
     * Loads a symbolic icon into a pixbuf, where the color-key has been switched to the provided
     * color.
     */
    public Gdk.Pixbuf? load_symbolic_colored(string icon_name, int size, Gdk.RGBA color,
        Gtk.IconLookupFlags flags = 0) {
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        
        // Attempt to load as a symbolic icon.
        if (icon_info != null) {
            try {
                return aspect_scale_down_pixbuf(icon_info.load_symbolic(color), size);
            } catch (Error e) {
                warning("Couldn't load icon: %s", e.message);
            }
        }
       // Default: missing image icon.
       return get_missing_icon(size, flags);
    }
    
}

