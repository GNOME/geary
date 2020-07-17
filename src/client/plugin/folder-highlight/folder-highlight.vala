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
        typeof(Plugin.FolderHighlight)
    );
}

/**
 * Manages highlighting folders that have newly delivered mail
 */
public class Plugin.FolderHighlight :
    PluginBase, NotificationExtension, FolderExtension, TrustedExtension {


    private const Geary.Folder.SpecialUse[] MONITORED_TYPES = {
        INBOX, NONE
    };


    public NotificationContext notifications {
        get; construct set;
    }

    public FolderContext folders {
        get; construct set;
    }

    public global::Application.Client client_application {
        get; construct set;
    }

    public global::Application.PluginManager client_plugins {
        get; construct set;
    }

    public override async void activate(bool is_startup) throws GLib.Error {
        this.notifications.new_messages_arrived.connect(on_new_messages_arrived);
        this.notifications.new_messages_retired.connect(on_new_messages_retired);

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
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        // no-op
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

    private void on_new_messages_arrived(Folder folder,
                                         int total,
                                         Gee.Collection<EmailIdentifier> added) {
        Geary.Folder? engine = this.client_plugins.to_engine_folder(folder);
        if (engine != null) {
            foreach (global::Application.MainWindow window
                     in this.client_application.get_main_windows()) {
                window.folder_list.set_has_new(engine, true);
            }
        }
    }

    private void on_new_messages_retired(Folder folder, int total) {
        Geary.Folder? engine = this.client_plugins.to_engine_folder(folder);
        if (engine != null) {
            foreach (global::Application.MainWindow window
                     in this.client_application.get_main_windows()) {
                window.folder_list.set_has_new(engine, false);
            }
        }
    }

}
