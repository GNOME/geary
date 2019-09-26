/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Finds and manages application plugins.
 */
public class Application.PluginManager : GLib.Object {


    public NotificationContext notifications { get; set; }

    private Peas.Engine engine;
    private Peas.ExtensionSet? notification_extensions = null;


    public PluginManager(GLib.File app_plugin_dir) {
        this.engine = Peas.Engine.get_default();
        this.engine.add_search_path(app_plugin_dir.get_path(), null);
    }

    public void load() {
        this.notification_extensions = new Peas.ExtensionSet(
            this.engine,
            typeof(Plugin.Notification),
            "context", this.notifications
        );
        this.notification_extensions.extension_added.connect((info, extension) => {
                (extension as Plugin.Notification).activate();
            });
        this.notification_extensions.extension_removed.connect((info, extension) => {
                (extension as Plugin.Notification).deactivate();
            });

        // Load built-in plugins by default
        foreach (Peas.PluginInfo info in this.engine.get_plugin_list()) {
            if (info.is_builtin()) {
                this.engine.load_plugin(info);
            }
        }
    }

}
