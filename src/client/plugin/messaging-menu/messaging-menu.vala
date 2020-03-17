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
        typeof(Plugin.MessagingMenu)
    );
}

/** Updates the Unity messaging menu when new mail arrives. */
public class Plugin.MessagingMenu : PluginBase, NotificationExtension {


    public NotificationContext notifications {
        get; set construct;
    }


    private global::MessagingMenu.App? app = null;
    private FolderStore? folders = null;


    public override void activate() {
        this.app = new global::MessagingMenu.App(
            "%s.desktop".printf(global::Application.Client.APP_ID)
        );
        this.app.register();
        this.app.activate_source.connect(on_activate_source);

        this.notifications.new_messages_arrived.connect(on_new_messages_changed);
        this.notifications.new_messages_retired.connect(on_new_messages_changed);
        this.connect_folders.begin();
    }

    public override void deactivate(bool is_shutdown) {
        this.app.activate_source.disconnect(on_activate_source);
        this.app.unregister();
        this.app = null;
    }

    private async void connect_folders() {
        try {
            this.folders = yield this.notifications.get_folders();
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
    }

    private void show_new_messages_count(Folder folder, int count) {
        if (this.notifications.should_notify_new_messages(folder)) {
            string source_id = get_source_id(folder);

            if (this.app.has_source(source_id)) {
                this.app.set_source_count(source_id, count);
            } else {
                this.app.append_source_with_count(
                    source_id,
                    null,
                    _("%s — New Messages").printf(folder.display_name),
                    count);
            }

            this.app.draw_attention(source_id);
        }
    }

    private void remove_new_messages_count(Folder folder) {
        string source_id = get_source_id(folder);
        if (this.app.has_source(source_id)) {
            this.app.remove_attention(source_id);
            this.app.remove_source(source_id);
        }
    }

    private string get_source_id(Folder folder) {
        return "geary%s".printf(folder.to_variant().print(false));
    }

    private void on_activate_source(string source_id) {
        if (this.folders != null) {
            foreach (Folder folder in this.folders.get_folders()) {
                if (source_id == get_source_id(folder)) {
                    this.plugin_application.show_folder(folder);
                    break;
                }
            }
        }
    }

    private void on_new_messages_changed(Folder folder, int count) {
        if (count > 0) {
            show_new_messages_count(folder, count);
        } else {
            remove_new_messages_count(folder);
        }
    }

    private void check_folders(Gee.Collection<Folder> folders) {
        foreach (Folder folder in folders) {
            if (folder.folder_type == INBOX) {
                this.notifications.start_monitoring_folder(folder);
            } else if (this.notifications.is_monitoring_folder(folder)) {
                this.notifications.stop_monitoring_folder(folder);
            }
        }
    }

}
