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
        typeof(Plugin.PluginBase),
        typeof(Plugin.NotificationBadge)
    );
}

/** Updates Unity application badge with total new message count. */
public class Plugin.NotificationBadge :
    PluginBase, NotificationExtension, FolderExtension, TrustedExtension {


    private const Geary.Folder.SpecialUse[] MONITORED_TYPES = {
        INBOX, NONE
    };

    public NotificationContext notifications {
        get; set construct;
    }

    public FolderContext folders {
        get; set construct;
    }

    public global::Application.Client client_application {
        get; set construct;
    }

    public global::Application.PluginManager client_plugins {
        get; set construct;
    }

    private UnityLauncherEntry? entry = null;


    public override async void activate(bool is_startup) throws GLib.Error {
        var connection = this.client_application.get_dbus_connection();
        var path = this.client_application.get_dbus_object_path();
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

        FolderStore folder_store = yield this.folders.get_folder_store();
        folder_store.folders_available.connect(
            (folders) => check_folders(folders)
        );
        folder_store.folders_unavailable.connect(
            (folders) => check_folders(folders)
        );
        folder_store.folders_type_changed.connect(
            (folders) => check_folders(folders)
        );
        check_folders(folder_store.get_folders());

        this.notifications.notify["total-new-messages"].connect(on_total_changed);
        update_count();
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.notifications.notify["total-new-messages"].disconnect(
            on_total_changed
        );
        this.entry = null;
    }

    private void check_folders(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.used_as in MONITORED_TYPES) {
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
