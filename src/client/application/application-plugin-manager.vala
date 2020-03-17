/*
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Finds and manages application plugins.
 */
public class Application.PluginManager : GLib.Object {


    // Plugins that will be loaded automatically and trusted with
    // access to the application if they have been installed
    private const string[] TRUSTED_MODULES = {
        "desktop-notifications",
        "messaging-menu",
        "notification-badge"
    };

    private Client application;
    private Peas.Engine engine;
    private bool is_shutdown = false;
    private string trusted_path;

    private Peas.ExtensionSet notification_extensions;
    private NotificationContext notifications;


    public PluginManager(Client application,
                         NotificationContext notifications) {
        this.application = application;
        this.engine = Peas.Engine.get_default();

        this.trusted_path = application.get_app_plugins_dir().get_path();
        this.plugins.add_search_path(trusted_path, null);

        this.notifications = notifications;
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

        string[] optional_names = application.config.get_optional_plugins();
        foreach (Peas.PluginInfo info in this.engine.get_plugin_list()) {
            string name = info.get_module_name();
            try {
                if (info.is_available()) {
                    if (is_trusted(info)) {
                        debug("Loading trusted plugin: %s", name);
                        this.engine.load_plugin(info);
                    } else if (name in optional_names) {
                        debug("Loading optional plugin: %s", name);
                        this.engine.load_plugin(info);
                    }
                }
            } catch (GLib.Error err) {
                warning("Plugin %s not available: %s", name, err.message);
            }
        }
    }

    public inline bool is_trusted(Peas.PluginInfo plugin) {
        return (
            plugin.get_module_name() in TRUSTED_MODULES &&
            plugin.get_module_dir().has_prefix(trusted_path)
        );
    }

    public Gee.Collection<Peas.PluginInfo> get_optional_plugins() {
        var plugins = new Gee.LinkedList<Peas.PluginInfo>();
        foreach (Peas.PluginInfo plugin in this.engine.get_plugin_list()) {
            try {
                plugin.is_available();
                if (!is_trusted(plugin)) {
                    plugins.add(plugin);
                }
            } catch (GLib.Error err) {
                warning(
                    "Plugin %s not available: %s",
                    plugin.get_module_name(), err.message
                );
            }
        }
        return plugins;
    }

    public bool load_optional(Peas.PluginInfo plugin) throws GLib.Error {
        bool loaded = false;
        if (plugin.is_available() &&
            !plugin.is_loaded() &&
            !is_trusted(plugin)) {
            this.plugins.load_plugin(plugin);
            loaded = true;
            string name = plugin.get_module_name();
            string[] optional_names =
                this.application.config.get_optional_plugins();
            if (!(name in optional_names)) {
                optional_names += name;
                this.application.config.set_optional_plugins(optional_names);
            }
        }
        return loaded;
    }

    public bool unload_optional(Peas.PluginInfo plugin) throws GLib.Error {
        bool unloaded = false;
        if (plugin.is_available() &&
            plugin.is_loaded() &&
            !is_trusted(plugin)) {
            this.plugins.unload_plugin(plugin);
            unloaded = true;
            string name = plugin.get_module_name();
            string[] old_names =
                this.application.config.get_optional_plugins();
            string[] new_names = new string[0];
            for (int i = 0; i < old_names.length; i++) {
                if (old_names[i] != name) {
                    new_names += old_names[i];
                }
            }
            this.application.config.set_optional_plugins(new_names);
        }
        return unloaded;
    }

    internal void close() throws GLib.Error {
        this.is_shutdown = true;
        this.plugins.set_loaded_plugins(null);
        this.folders_factory.destroy();
    }

}
