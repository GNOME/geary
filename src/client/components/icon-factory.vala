/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Singleton class to hold icons.
public class IconFactory {
    public const Gtk.IconSize ICON_TOOLBAR = Gtk.IconSize.LARGE_TOOLBAR;
    public const Gtk.IconSize ICON_SIDEBAR = Gtk.IconSize.MENU;


    public static IconFactory? instance { get; private set; }


    public static void init(GLib.File resource_directory) {
        IconFactory.instance = new IconFactory(resource_directory);
    }


    public const int UNREAD_ICON_SIZE = 16;
    public const int STAR_ICON_SIZE = 16;

    private Gtk.IconTheme icon_theme { get; private set; }

    private File icons_dir;

    // Creates the icon factory.
    private IconFactory(GLib.File resource_directory) {
        icons_dir = resource_directory.get_child("icons");
        icon_theme = Gtk.IconTheme.get_default();
        icon_theme.append_search_path(icons_dir.get_path());
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
        if (icon_info == null) {
            icon_info = icon_theme.lookup_icon("text-x-generic-symbolic", size, flags);
        }
        return icon_info;
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

