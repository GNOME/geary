/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Utility functions for GIO objects.
 */
namespace GioUtil {

    public const string GEARY_RESOURCE_PREFIX = "/org/gnome/Geary/";

    /**
     * Creates a GTK builder given the name of a GResource.
     *
     * The given `name` will automatically have
     * `GEARY_RESOURCE_PREFIX` pre-pended to it.
     */
    public Gtk.Builder create_builder(string name) {
        Gtk.Builder builder = new Gtk.Builder();
        try {
            builder.add_from_resource(GEARY_RESOURCE_PREFIX + name);
        } catch(GLib.Error error) {
            critical("Unable load GResource \"%s\" for Gtk.Builder: %s".printf(
                name, error.message
            ));
        }
        return builder;
    }

    /**
     * Loads a GResource file as a string.
     *
     * The given `name` will automatically have
     * `GEARY_RESOURCE_PREFIX` pre-pended to it.
     */
    public string read_resource(string name) throws Error {
        InputStream input_stream = resources_open_stream(
            GEARY_RESOURCE_PREFIX + name,
            ResourceLookupFlags.NONE
        );
        DataInputStream data_stream = new DataInputStream(input_stream);
        size_t length;
        return data_stream.read_upto("\0", 1, out length);
    }

}
