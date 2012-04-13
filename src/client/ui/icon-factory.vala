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
    
    public const int UNREAD_ICON_SIZE = 16;
    public Gdk.Pixbuf unread { get; private set; }

    public const int STAR_ICON_SIZE = 16;
    public Gdk.Pixbuf starred { get; private set; }
    public Gdk.Pixbuf unstarred { get; private set; }

    public const int GEARY_ICON_SIZE = 95;
    public Gdk.Pixbuf geary { get; private set; }
    
    public ThemedIcon label_icon { get; private set; default = new ThemedIcon("one-tag"); }
    public ThemedIcon label_folder_icon { get; private set; default = new ThemedIcon("multiple-tags"); }
    
    private Gtk.IconTheme icon_theme { get; private set; }
    
    private Gdk.Pixbuf? load(string icon_name, int size, Gtk.IconLookupFlags flags = 0) {
        // First try the requested image.
        try {
            return icon_theme.load_icon(icon_name, size, flags);
        } catch (Error e) {
            warning("Couldn't load icon. Error: " + e.message);
        }

        // If that fails, try the missing image icon instead.
        try {
            return icon_theme.load_icon("image-missing", size, flags);
        } catch (Error e) {
            warning("Couldn't load image-missing icon. Error: " + e.message);
        }

        // If that fails... well they're out of luck.
        return null;
    }

    public Gtk.IconInfo? lookup_icon(string icon_name, int size, Gtk.IconLookupFlags flags = 0) {
        Gtk.IconInfo? icon_info = icon_theme.lookup_icon(icon_name, size, flags);
        return icon_info != null ? icon_info.copy() :
            icon_theme.lookup_icon("image-missing", size, flags);
    }

    // Creates the icon factory.
    private IconFactory() {
        icon_theme= Gtk.IconTheme.get_default();
        icon_theme.append_search_path(GearyApplication.instance.get_resource_directory().
            get_child("icons").get_path());
        
        // Load icons here.
        unread = load("mail-unread", UNREAD_ICON_SIZE);
        starred = load("starred", STAR_ICON_SIZE);
        unstarred = load("non-starred-grey", STAR_ICON_SIZE);
        geary = load("geary", GEARY_ICON_SIZE);
    }
}

