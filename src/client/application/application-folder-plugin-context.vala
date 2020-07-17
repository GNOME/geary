/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Implementation of the folder plugin extension context.
 */
internal class Application.FolderPluginContext :
    Geary.BaseObject, Plugin.FolderContext {


    private unowned Client application;
    private PluginManager.PluginGlobals globals;
    private PluginManager.PluginContext plugin;
    private Plugin.FolderStore folders;


    internal FolderPluginContext(Client application,
                                 PluginManager.PluginGlobals globals,
                                 PluginManager.PluginContext plugin) {
        this.application = application;
        this.globals = globals;
        this.plugin = plugin;
        this.folders = globals.folders.new_folder_store();
    }

    public async Plugin.FolderStore get_folder_store()
        throws Plugin.Error.PERMISSION_DENIED {
        return this.folders;
    }

    public void add_folder_info_bar(Plugin.Folder selected,
                                    Plugin.InfoBar info_bar,
                                    uint priority) {
        Geary.Folder? folder = this.globals.folders.to_engine_folder(selected);
        if (folder != null) {
            foreach (MainWindow main in this.application.get_main_windows()) {
                if (main.selected_folder == folder) {
                    main.conversation_list_info_bars.add(
                        new Components.InfoBar.for_plugin(
                            info_bar,
                            this.plugin.action_group_name,
                            (int) priority
                        )
                    );
                }
            }
        }
    }

    public void remove_folder_info_bar(Plugin.Folder selected,
                                       Plugin.InfoBar info_bar) {
        Geary.Folder? folder = this.globals.folders.to_engine_folder(selected);
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

    public void register_folder_used_as(Plugin.Folder target,
                                        string name,
                                        string icon_name) throws Plugin.Error {
        var context = this.globals.folders.to_folder_context(target);
        if (context != null) {
            try {
                context.folder.set_used_as_custom(true);
            } catch (Geary.EngineError err) {
                throw new Plugin.Error.NOT_SUPPORTED(
                    "Failed to register folder use: %s", err.message
                );
            }
            context.display_name = name;
            context.icon_name = icon_name;
        }
    }

    public void unregister_folder_used_as(Plugin.Folder target)
        throws Plugin.Error {
        var context = this.globals.folders.to_folder_context(target);
        if (context != null) {
            try {
                context.folder.set_used_as_custom(false);
            } catch (Geary.EngineError err) {
                throw new Plugin.Error.NOT_SUPPORTED(
                    "Failed to unregister folder use: %s", err.message
                );
            }
        }
    }

    internal void destroy() {
        this.globals.folders.destroy_folder_store(this.folders);
    }

}
