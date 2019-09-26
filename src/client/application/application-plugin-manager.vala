/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/*
 * Finds and manages application plugins.
 */
public class Application.PluginManager : GLib.Object {


    public NotificationContext notifications { get; set; }

    private Peas.Engine engine;


    public PluginManager(GLib.File app_plugin_dir) {
        this.engine = Peas.Engine.get_default();
        this.engine.add_search_path(app_plugin_dir.get_path(), null);

        // Load built-in plugins
        foreach (Peas.PluginInfo info in this.engine.get_plugin_list()) {
            if (info.is_builtin()) {
                this.engine.load_plugin(info);
            }
        }
    }

}
