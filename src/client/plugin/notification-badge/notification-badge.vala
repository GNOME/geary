/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[ModuleInit]
public void peas_register_types(TypeModule module) {
    Peas.ObjectModule obj = module as Peas.ObjectModule;
    obj.register_extension_type(
        typeof(Plugin.Notification),
        typeof(Plugin.NotificationBadge)
    );
}

/** Updates Unity application badge with total new message count. */
public class Plugin.NotificationBadge : Notification {


    public override Application.Client application {
        get; construct set;
    }

    public override Application.NotificationContext context {
        get; construct set;
    }

    private UnityLauncherEntry? entry = null;


    public override void activate() {
        var connection = this.application.get_dbus_connection();
        var path = this.application.get_dbus_object_path();
        try {
            if (connection == null || path == null) {
                throw new GLib.IOError.NOT_CONNECTED(
                    "Application does not have a DBus connection or path"
                );
            }
            this.entry = new UnityLauncherEntry(
                connection,
                path + "/plugin/notificationbadge",
                Application.Client.APP_ID + ".desktop"
            );
        } catch (GLib.Error error) {
            warning(
                "Failed to register Unity Launcher Entry: %s",
                error.message
            );
        }

        this.context.notify["total-new-messages"].connect(on_total_changed);
        update_count();
    }

    public override void deactivate(bool is_shutdown) {
        this.context.notify["total-new-messages"].disconnect(on_total_changed);
        this.entry = null;
    }

    private void update_count() {
        if (this.entry != null) {
            int count = this.context.total_new_messages;
            if (count > 0) {
                this.entry.set_count(count);
            } else {
                this.entry.clear_count();
            }
        }
    }

    private void on_total_changed() {
        update_count();
    }

}
