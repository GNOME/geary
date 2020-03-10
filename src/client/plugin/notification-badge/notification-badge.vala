/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>.
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
public class Plugin.NotificationBadge : Geary.BaseObject, Notification {


    private const Geary.SpecialFolderType[] MONITORED_TYPES = {
        INBOX, NONE
    };

    public global::Application.NotificationContext notifications {
        get; set;
    }

    private UnityLauncherEntry? entry = null;


    public override void activate() {
        try {
            var application = this.notifications.get_client_application();
            var connection = application.get_dbus_connection();
            var path = application.get_dbus_object_path();
            if (connection == null || path == null) {
                throw new GLib.IOError.NOT_CONNECTED(
                    "Application does not have a DBus connection or path"
                );
            }
            this.entry = new UnityLauncherEntry(
                connection,
                path + "/plugin/notificationbadge",
                global::Application.Client.APP_ID + ".desktop"
            );
        } catch (GLib.Error error) {
            warning(
                "Failed to register Unity Launcher Entry: %s",
                error.message
            );
        }

        connect_folders.begin();
    }

    public override void deactivate(bool is_shutdown) {
        this.notifications.notify["total-new-messages"].disconnect(
            on_total_changed
        );
        this.entry = null;
    }

    public async void connect_folders() {
        try {
            FolderStore folders = yield this.notifications.get_folders();
            folders.folders_available.connect(
                (folders) => check_folders(folders)
            );
            folders.folders_unavailable.connect(
                (folders) => check_folders(folders)
            );
            folders.folders_type_changed.connect(
                (folders) => check_folders(folders)
            );
            check_folders(folders.get_folders());
        } catch (GLib.Error error) {
            warning(
                "Unable to get folders for plugin: %s",
                error.message
            );
        }

        this.notifications.notify["total-new-messages"].connect(on_total_changed);
        update_count();
    }

    private void check_folders(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.folder_type in MONITORED_TYPES) {
                this.notifications.start_monitoring_folder(folder);
            } else {
                this.notifications.stop_monitoring_folder(folder);
            }
        }
    }

    private void update_count() {
        if (this.entry != null) {
            int count = this.notifications.total_new_messages;
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
