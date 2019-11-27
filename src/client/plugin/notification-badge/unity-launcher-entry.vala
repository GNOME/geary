/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A simple, high-level interface for the Unity Launcher API.
 *
 * See https://wiki.ubuntu.com/Unity/LauncherAPI for documentation.
 */
public class UnityLauncherEntry : Geary.BaseObject {


    private const string DBUS_NAME = "com.canonical.Unity.LauncherEntry";


    [DBus (name = "com.canonical.Unity.LauncherEntry")]
    private class Entry : Geary.BaseObject {


        public signal void update (string app_uri,
                                   HashTable<string,Variant> properties);

    }

    private string app_uri;
    private Entry entry = new Entry();
    private GLib.DBusConnection connection;
    private uint object_id;
    private uint watch_id;

    // Launcher entry properties
    private int64 count = 0;
    private bool count_visible = false;


    /**
     * Constructions a new launcher entry for the given DBus connection.
     *
     * The given path is used as the path of the DBus object that
     * interacts with the Uniti API, and should be bus-unique. The
     * given desktop identifier must match the name of the desktop
     * file for the application.
     */
    public UnityLauncherEntry(GLib.DBusConnection connection,
                              string dbus_path,
                              string desktop_id)
        throws GLib.Error {
        this.app_uri = "application://%s".printf(desktop_id);
        this.connection = connection;
        this.object_id = connection.register_object(dbus_path, this.entry);
        this.watch_id = GLib.Bus.watch_name_on_connection(
            connection,
            DBUS_NAME,
            NONE,
            on_name_appeared,
            null
        );

        update_all();
    }

    ~UnityLauncherEntry() {
        GLib.Bus.unwatch_name(this.watch_id);
        this.connection.unregister_object(this.object_id);
    }

    /** Sets and shows the count for the application. */
    public void set_count(int64 count) {
        var props = new_properties();
        if (this.count != count) {
            this.count = count;
            put_count(props);
        }
        if (!this.count_visible) {
            this.count_visible = true;
            put_count_visible(props);
        }
        send(props);
    }

    /** Clears and hides any count for the application. */
    public void clear_count() {
        var props = new_properties();
        if (this.count != 0) {
            this.count = 0;
            put_count(props);
        }
        if (this.count_visible) {
            this.count_visible = false;
            put_count_visible(props);
        }
        send(props);
    }

    private void update_all() {
        var props = new_properties();
        if (this.count != 0) {
            put_count(props);
        }
        if (!this.count_visible) {
            put_count_visible(props);
        }
        send(props);
    }

    private void send(GLib.HashTable<string,GLib.Variant> properties) {
        if (properties.size() > 0) {
            this.entry.update(this.app_uri, properties);
        }
    }

    private GLib.HashTable<string,GLib.Variant> new_properties() {
        return new GLib.HashTable<string,GLib.Variant>(str_hash, str_equal);
    }

    private void put_count(GLib.HashTable<string,GLib.Variant> properties) {
        properties.insert(
            "count", new GLib.Variant.int64(this.count)
        );
    }

    private void put_count_visible(GLib.HashTable<string,GLib.Variant> properties) {
        properties.insert(
            "count-visible",
            new GLib.Variant.boolean(this.count_visible)
        );
    }

    private void on_name_appeared() {
        update_all();
    }

}
