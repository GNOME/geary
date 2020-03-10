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

    /** Flags assigned to a plugin by the manager. */
    [Flags]
    public enum PluginFlags {
        /** If set, the plugin is in the set of trusted plugins. */
        TRUSTED;
    }


    private Client application;
    private Peas.Engine plugins;
    private bool is_shutdown = false;
    private string trusted_path;

    private FolderStoreFactory folders_factory;

    private Peas.ExtensionSet notification_extensions;
    private Gee.Set<NotificationContext> notification_contexts =
        new Gee.HashSet<NotificationContext>();


    public PluginManager(Client application) throws GLib.Error {
        this.application = application;
        this.plugins = Peas.Engine.get_default();
        this.folders_factory = new FolderStoreFactory(application.engine);

        this.trusted_path = application.get_app_plugins_dir().get_path();
        this.plugins.add_search_path(trusted_path, null);

        this.notification_extensions = new Peas.ExtensionSet(
            this.plugins,
            typeof(Plugin.Notification)
        );
        this.notification_extensions.extension_added.connect((info, extension) => {
                Plugin.Notification? plugin = extension as Plugin.Notification;
                if (plugin != null) {
                    var context = new NotificationContext(
                        this.application,
                        this.folders_factory,
                        to_plugin_flags(info)
                    );
                    this.notification_contexts.add(context);
                    plugin.notifications = context;
                    plugin.activate();
                }
            });
        this.notification_extensions.extension_removed.connect((info, extension) => {
                Plugin.Notification? plugin = extension as Plugin.Notification;
                if (plugin != null) {
                    plugin.deactivate(this.is_shutdown);
                }
                var context = plugin.notifications;
                context.destroy();
                this.notification_contexts.remove(context);
            });

        string[] optional_names = application.config.get_optional_plugins();
        foreach (Peas.PluginInfo info in this.plugins.get_plugin_list()) {
            string name = info.get_module_name();
            try {
                if (info.is_available()) {
                    if (is_trusted(info)) {
                        debug("Loading trusted plugin: %s", name);
                        this.plugins.load_plugin(info);
                    } else if (name in optional_names) {
                        debug("Loading optional plugin: %s", name);
                        this.plugins.load_plugin(info);
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

    public inline PluginFlags to_plugin_flags(Peas.PluginInfo plugin) {
        return is_trusted(plugin) ? PluginFlags.TRUSTED : 0;
    }

    public Gee.Collection<Peas.PluginInfo> get_optional_plugins() {
        var plugins = new Gee.LinkedList<Peas.PluginInfo>();
        foreach (Peas.PluginInfo plugin in this.plugins.get_plugin_list()) {
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

    internal Gee.Collection<NotificationContext> get_notification_contexts() {
        return this.notification_contexts.read_only_view;
    }

}
