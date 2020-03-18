/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Implementation of the folder extension context.
 */
internal class Application.FolderContext :
    Geary.BaseObject, Plugin.FolderContext {


    private class PluginInfoBar : Components.InfoBar {


        private Plugin.InfoBar plugin;


        public PluginInfoBar(Plugin.InfoBar plugin) {
            base(plugin.status, plugin.description);
            this.show_close_button = plugin.show_close_button;
            this.plugin = plugin;
        }

    }


    private unowned Client application;
    private FolderStoreFactory folders_factory;
    private Plugin.FolderStore folders;


    internal FolderContext(Client application,
                           FolderStoreFactory folders_factory) {
        this.application = application;
        this.folders_factory = folders_factory;
        this.folders = folders_factory.new_folder_store();
    }

    public async Plugin.FolderStore get_folders()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.folders;
    }

    public void add_folder_info_bar(Plugin.Folder selected,
                                    Plugin.InfoBar infobar,
                                    uint priority) {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(selected);
        if (folder != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.selected_folder == folder) {
                    main.conversation_list_info_bars.add(
                        new PluginInfoBar(infobar)
                    );
                }
            }
        }
    }

    public void remove_folder_info_bar(Plugin.Folder selected,
                                       Plugin.InfoBar infobar) {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(selected);
        if (folder != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.selected_folder == folder) {
                    main.conversation_list_info_bars.remove(
                        new PluginInfoBar(infobar)
                    );
                }
            }
        }
    }

    internal void destroy() {
        this.folders_factory.destroy_folder_store(this.folders);
    }

}
