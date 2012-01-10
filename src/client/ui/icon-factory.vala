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
    
    public const int UNREAD_ICON_SIZE = 12;
    public Gdk.Pixbuf? unread { get; private set; }
    
    private static Gdk.Pixbuf? load(string icon_name, int size, Gtk.IconLookupFlags flags = 0) {
        try {
            return Gtk.IconTheme.get_default().load_icon(icon_name, size, flags);
        } catch (Error e) {
            warning("Couldn't load icon. Error: " + e.message);
        }
        
        return null;
    }
    
    // Creats the icon factory.
    private IconFactory() {
        // Load icons here.
        unread = load(Gtk.Stock.YES, UNREAD_ICON_SIZE);
    }
}

