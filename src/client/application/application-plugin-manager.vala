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


    // Plugins that will be loaded automatically when the client
    // application stats up
    private const string[] AUTOLOAD_MODULES = {
        "desktop-notifications",
        "notification-badge",
    };


    private class ApplicationImpl : Geary.BaseObject, Plugin.Application {


        private Client backing;
        private FolderStoreFactory folders;


        public ApplicationImpl(Client backing,
                               FolderStoreFactory folders) {
            this.backing = backing;
            this.folders = folders;
        }

        public override void show_folder(Plugin.Folder folder) {
            Geary.Folder? target = this.folders.get_engine_folder(folder);
            if (target != null) {
                this.backing.show_folder.begin(target);
            }
        }

    }


    private Client application;
    private Peas.Engine plugins;
    private bool is_shutdown = false;
    private string trusted_path;

    private FolderStoreFactory folders_factory;

    private Gee.Map<Peas.PluginInfo,Plugin.PluginBase> plugin_set =
        new Gee.HashMap<Peas.PluginInfo,Plugin.PluginBase>();
    private Gee.Map<Peas.PluginInfo,NotificationContext> notification_contexts =
        new Gee.HashMap<Peas.PluginInfo,NotificationContext>();


    public PluginManager(Client application) throws GLib.Error {
        this.application = application;
        this.plugins = Peas.Engine.get_default();
        this.folders_factory = new FolderStoreFactory(application.engine);

        this.trusted_path = application.get_app_plugins_dir().get_path();
        this.plugins.add_search_path(trusted_path, null);

        this.plugins.load_plugin.connect_after(on_load_plugin);
        this.plugins.unload_plugin.connect(on_unload_plugin);

        string[] optional_names = application.config.get_optional_plugins();
        foreach (Peas.PluginInfo info in this.plugins.get_plugin_list()) {
            string name = info.get_module_name();
            try {
                if (info.is_available()) {
                    if (is_autoload(info)) {
                        debug("Loading autoload plugin: %s", name);
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

    /** Returns the engine folder for the given plugin folder, if any. */
    public Geary.Folder? get_engine_folder(Plugin.Folder plugin) {
        return this.folders_factory.get_engine_folder(plugin);
    }

    public Gee.Collection<Peas.PluginInfo> get_optional_plugins() {
        var plugins = new Gee.LinkedList<Peas.PluginInfo>();
        foreach (Peas.PluginInfo plugin in this.plugins.get_plugin_list()) {
            try {
                plugin.is_available();
                if (!is_autoload(plugin)) {
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
            !is_autoload(plugin)) {
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
            !is_autoload(plugin)) {
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
        this.plugins.garbage_collect();
        this.folders_factory.destroy();
    }

    internal inline bool is_autoload(Peas.PluginInfo info) {
        return info.get_module_name() in AUTOLOAD_MODULES;
    }

    internal Gee.Collection<NotificationContext> get_notification_contexts() {
        return this.notification_contexts.values.read_only_view;
    }

    private void on_load_plugin(Peas.PluginInfo info) {
        var plugin = this.plugins.create_extension(
            info,
            typeof(Plugin.PluginBase),
            "plugin_application",
            new ApplicationImpl(this.application, this.folders_factory)
        ) as Plugin.PluginBase;
        if (plugin != null) {
            bool do_activate = true;
            var trusted = plugin as Plugin.TrustedExtension;
            if (trusted != null) {
                if (info.get_module_dir().has_prefix(this.trusted_path)) {
                    trusted.client_application = this.application;
                    trusted.client_plugins = this;
                } else {
                    do_activate = false;
                    this.plugins.unload_plugin(info);
                }
            }

            var notification = plugin as Plugin.NotificationExtension;
            if (notification != null) {
                var context = new NotificationContext(
                    this.application,
                    this.folders_factory
                );
                this.notification_contexts.set(info, context);
                notification.notifications = context;
            }

            if (do_activate) {
                this.plugin_set.set(info, plugin);
                plugin.activate();
            }
        } else {
            warning(
                "Could not construct BasePlugin from %s", info.get_module_name()
            );
        }
    }

    private void on_unload_plugin(Peas.PluginInfo info) {
        var plugin = this.plugin_set.get(info);
        if (plugin != null) {
            plugin.deactivate(this.is_shutdown);

            var notification = plugin as Plugin.NotificationExtension;
            if (notification != null) {
                var context = this.notification_contexts.get(info);
                if (context != null) {
                    this.notification_contexts.unset(info);
                    context.destroy();
                }
            }

            this.plugin_set.unset(info);
        }
    }

}
