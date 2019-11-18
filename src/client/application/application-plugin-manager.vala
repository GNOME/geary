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

    private Client application;
    private Peas.Engine engine;
    private Peas.ExtensionSet? notification_extensions = null;
    private bool is_shutdown = false;


    public PluginManager(Client application) {
        this.application = application;
        this.engine = Peas.Engine.get_default();
        this.engine.add_search_path(
            application.get_app_plugins_dir().get_path(), null
        );
    }

    public void load() {
        this.notification_extensions = new Peas.ExtensionSet(
            this.engine,
            typeof(Plugin.Notification),
            "application", this.application,
            "context", this.notifications
        );
        this.notification_extensions.extension_added.connect((info, extension) => {
                Plugin.Notification? plugin = extension as Plugin.Notification;
                if (plugin != null) {
                    plugin.activate();
                }
            });
        this.notification_extensions.extension_removed.connect((info, extension) => {
                Plugin.Notification? plugin = extension as Plugin.Notification;
                if (plugin != null) {
                    plugin.deactivate(this.is_shutdown);
                }
            });

        // Load built-in plugins by default
        foreach (Peas.PluginInfo info in this.engine.get_plugin_list()) {
            try {
                info.is_available();
                if (info.is_builtin()) {
                    debug("Loading built-in plugin: %s", info.get_name());
                    this.engine.load_plugin(info);
                } else {
                    debug("Not loading plugin: %s", info.get_name());
                }
            } catch (GLib.Error err) {
                warning("Plugin %s not available: %s",
                        info.get_name(), err.message);
            }
        }
    }

}
