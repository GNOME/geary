/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// Singleton class to hold icons.
public class IconFactory {
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

    public const int STAR_ICON_SIZE = 16;
    public Gdk.Pixbuf starred { get; private set; }
    public Gdk.Pixbuf unstarred { get; private set; }

    public ThemedIcon label_icon { get; private set; default = new ThemedIcon("tag"); }
    public ThemedIcon label_folder_icon { get; private set; default = new ThemedIcon("tag"); }
    
    private Gtk.IconTheme icon_theme { get; private set; }
    
    // Creates the icon factory.
    private IconFactory() {
        icon_theme = Gtk.IconTheme.get_default();
        
        append_icons_search_path(null);
        append_icons_search_path("128x128");
        append_icons_search_path("48x48");
        append_icons_search_path("24x24");
        append_icons_search_path("16x16");
        
        // Load icons here.
        application_icon = load("geary", APPLICATION_ICON_SIZE);
        unread = load("mail-unread", UNREAD_ICON_SIZE);
        starred = load("starred", STAR_ICON_SIZE);
        unstarred = load("non-starred-grey", STAR_ICON_SIZE);
    }
    
    private void append_icons_search_path(string? name) {
        File basedir = GearyApplication.instance.get_resource_directory().get_child("icons");
        
        if (Geary.String.is_empty(name))
            icon_theme.append_search_path(basedir.get_path());
        else
            icon_theme.append_search_path(basedir.get_child(name).get_path());
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
        
        // If that fails, try the missing image icon instead.
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
            icon_theme.lookup_icon("image-missing", size, flags);
    }
}

