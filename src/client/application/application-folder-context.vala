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


    private unowned Client application;
    private FolderStoreFactory folders_factory;
    private Plugin.FolderStore folders;
    private string action_group_name;


    internal FolderContext(Client application,
                           FolderStoreFactory folders_factory,
                           string action_group_name) {
        this.application = application;
        this.folders_factory = folders_factory;
        this.folders = folders_factory.new_folder_store();
        this.action_group_name = action_group_name;
    }

    public async Plugin.FolderStore get_folders()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.folders;
    }

    public void add_folder_info_bar(Plugin.Folder selected,
                                    Plugin.InfoBar info_bar,
                                    uint priority) {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(selected);
        if (folder != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.selected_folder == folder) {
                    main.conversation_list_info_bars.add(
                        new Components.InfoBar.for_plugin(
                            info_bar, this.action_group_name
                        )
                    );
                }
            }
        }
    }

    public void remove_folder_info_bar(Plugin.Folder selected,
                                       Plugin.InfoBar info_bar) {
        Geary.Folder? folder = this.folders_factory.get_engine_folder(selected);
        if (folder != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.selected_folder == folder) {
                    // XXX implement this
                    //main.conversation_list_info_bars.remove(
                    //    XXX
                    //);
                }
            }
        }
    }

    internal void destroy() {
        this.folders_factory.destroy_folder_store(this.folders);
    }

}
