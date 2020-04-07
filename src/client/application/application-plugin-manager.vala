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
        "folder-highlight",
        "notification-badge",
        "special-folders",
    };


    private class PluginContext {


        public Peas.PluginInfo info { get; private set; }
        public Plugin.PluginBase plugin { get; private set; }


        public PluginContext(Peas.PluginInfo info, Plugin.PluginBase plugin) {
            this.info = info;
            this.plugin = plugin;
        }

        public async void activate() throws GLib.Error {
            yield this.plugin.activate();
        }

        public async void deactivate(bool is_shutdown) throws GLib.Error {
            yield this.plugin.deactivate(is_shutdown);
        }

    }


    private class ApplicationImpl : Geary.BaseObject, Plugin.Application {


        internal string action_group_name { get; private set; }

        private Peas.PluginInfo plugin;
        private Client backing;
        private FolderStoreFactory folders;
        private GLib.SimpleActionGroup? action_group = null;


        public ApplicationImpl(Peas.PluginInfo plugin,
                               Client backing,
                               FolderStoreFactory folders) {
            this.plugin = plugin;
            this.backing = backing;
            this.folders = folders;
            this.action_group_name = plugin.get_module_name().replace(".", "_");
        }

        public Plugin.Composer new_composer(Plugin.Account source)
            throws Plugin.Error {
            var impl = source as AccountImpl;
            if (impl == null) {
                throw new Plugin.Error.NOT_SUPPORTED("Not a valid account");
            }
            return new ComposerImpl(this.backing, impl.backing);
        }

        public void register_action(GLib.Action action) {
            if (this.action_group == null) {
                this.action_group = new GLib.SimpleActionGroup();
                this.backing.window_added.connect(on_window_added);
                foreach (MainWindow main in this.backing.get_main_windows()) {
                    main.insert_action_group(
                        this.action_group_name,
                        this.action_group
                    );
                }
            }

            this.action_group.add_action(action);
        }

        public void deregister_action(GLib.Action action) {
            this.action_group.remove_action(action.get_name());
        }

        public void show_folder(Plugin.Folder folder) {
            Geary.Folder? target = this.folders.get_engine_folder(folder);
            if (target != null) {
                this.backing.show_folder.begin(target);
            }
        }

        public async void empty_folder(Plugin.Folder folder)
           throws Plugin.Error.PERMISSION_DENIED {
           MainWindow main = this.backing.last_active_main_window;
           if (main == null) {
               throw new Plugin.Error.PERMISSION_DENIED(
                   "Cannot prompt for permission"
               );
           }

           Geary.Folder? target = this.folders.get_engine_folder(folder);
           if (target != null) {
               if (!main.prompt_empty_folder(target.used_as)) {
                   throw new Plugin.Error.PERMISSION_DENIED(
                       "Permission not granted"
                   );
               }

               Application.Controller controller = this.backing.controller;
               controller.empty_folder.begin(
                   target,
                   (obj, res) => {
                       try {
                           controller.empty_folder.end(res);
                       } catch (GLib.Error error) {
                           controller.report_problem(
                               new Geary.AccountProblemReport(
                                   target.account.information,
                                   error
                               )
                           );
                       }
                   }
               );
           }
        }

        private void on_window_added(Gtk.Window window) {
            if (this.action_group != null) {
                var main = window as MainWindow;
                if (main != null) {
                    main.insert_action_group(
                        this.action_group_name,
                        this.action_group
                    );
                }
            }
        }

    }


    internal class AccountImpl : Geary.BaseObject, Plugin.Account {


        public string display_name {
            get { return this.backing.account.information.display_name; }
        }


        /** The underlying backing account context for this account. */
        internal AccountContext backing { get; private set; }


        public AccountImpl(AccountContext backing) {
            this.backing = backing;
        }

    }


    private class ComposerImpl : Geary.BaseObject, Plugin.Composer {


        private Client application;
        private AccountContext account;


        public ComposerImpl(Client application, AccountContext account) {
            this.application = application;
            this.account = account;
        }

        public void show() {
            var composer = new Composer.Widget(
                this.application, this.account.account, NEW_MESSAGE
            );
            var main_window = this.application.get_active_main_window();
            main_window.show_composer(composer, null);
            composer.load.begin(null, false, null, null);
        }

    }


    /** Emitted when a plugin is successfully loaded and activated. */
    public signal void plugin_activated(Peas.PluginInfo info);

    /** Emitted when a plugin raised an error loading or activating. */
    public signal void plugin_error(Peas.PluginInfo info, GLib.Error error);

    /**
     * Emitted when a plugin was unloaded.
     *
     * If the given error is not null, it was raised on deactivate.
     */
    public signal void plugin_deactivated(Peas.PluginInfo info,
                                          GLib.Error? error);


    private Client application;
    private Controller controller;
    private Configuration config;
    private Peas.Engine plugins;
    private bool is_shutdown = false;
    private string trusted_path;

    private Gee.Map<Geary.AccountInformation,AccountImpl> plugin_accounts =
        new Gee.HashMap<Geary.AccountInformation,AccountImpl>();
    private FolderStoreFactory folders_factory;
    private EmailStoreFactory email_factory;

    private Gee.Map<Peas.PluginInfo,PluginContext> plugin_set =
        new Gee.HashMap<Peas.PluginInfo,PluginContext>();
    private Gee.Map<Peas.PluginInfo,NotificationPluginContext> notification_contexts =
        new Gee.HashMap<Peas.PluginInfo,NotificationPluginContext>();
    private Gee.Map<Peas.PluginInfo,EmailPluginContext> email_contexts =
        new Gee.HashMap<Peas.PluginInfo,EmailPluginContext>();


    internal PluginManager(Client application,
                           Controller controller,
                           Configuration config,
                           GLib.File trusted_plugin_path) throws GLib.Error {
        this.application = application;
        this.controller = controller;
        this.config = config;
        this.plugins = Peas.Engine.get_default();
        this.folders_factory = new FolderStoreFactory(
            controller, this.plugin_accounts.read_only_view
        );
        this.email_factory = new EmailStoreFactory(
            controller, this.plugin_accounts.read_only_view
        );

        this.trusted_path = trusted_plugin_path.get_path();
        this.plugins.add_search_path(this.trusted_path, null);

        this.plugins.load_plugin.connect_after(on_load_plugin);
        this.plugins.unload_plugin.connect(on_unload_plugin);

        string[] optional_names = this.config.get_optional_plugins();
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

        this.controller.account_available.connect(
            on_account_available
        );
        this.controller.account_unavailable.connect(
            on_account_unavailable
        );
        foreach (var context in this.controller.get_account_contexts()) {
            add_account(context);
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
            string[] optional_names = this.config.get_optional_plugins();
            if (!(name in optional_names)) {
                optional_names += name;
                this.config.set_optional_plugins(optional_names);
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
            string[] old_names = this.config.get_optional_plugins();
            string[] new_names = new string[0];
            for (int i = 0; i < old_names.length; i++) {
                if (old_names[i] != name) {
                    new_names += old_names[i];
                }
            }
            this.config.set_optional_plugins(new_names);
        }
        return unloaded;
    }

    internal void close() throws GLib.Error {
        this.is_shutdown = true;

        this.controller.account_unavailable.disconnect(on_account_unavailable);
        this.controller.account_available.disconnect(on_account_available);
        foreach (var context in this.controller.get_account_contexts()) {
            remove_account(context);
        }

        this.plugins.set_loaded_plugins(null);
        this.plugins.garbage_collect();
        this.folders_factory.destroy();
        this.email_factory.destroy();
    }

    internal inline bool is_autoload(Peas.PluginInfo info) {
        return info.get_module_name() in AUTOLOAD_MODULES;
    }

    internal Gee.Collection<NotificationPluginContext> get_notification_contexts() {
        return this.notification_contexts.values.read_only_view;
    }

    internal Gee.Collection<EmailPluginContext> get_email_contexts() {
        return this.email_contexts.values.read_only_view;
    }

    internal void add_account(AccountContext added) {
        this.plugin_accounts.set(added.account.information, new AccountImpl(added));
        this.folders_factory.add_account(added);
    }

    internal void remove_account(AccountContext removed) {
        this.folders_factory.remove_account(removed);
        this.plugin_accounts.unset(removed.account.information);
    }

    private void on_load_plugin(Peas.PluginInfo info) {
        var plugin_application = new ApplicationImpl(
            info, this.application, this.folders_factory
        );
        var plugin = this.plugins.create_extension(
            info,
            typeof(Plugin.PluginBase),
            "plugin_application",
            plugin_application
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
                var context = new NotificationPluginContext(
                    this.application,
                    this.folders_factory,
                    this.email_factory
                );
                this.notification_contexts.set(info, context);
                notification.notifications = context;
            }

            var email = plugin as Plugin.EmailExtension;
            if (email != null) {
                var context = new EmailPluginContext(
                    this.application,
                    this.email_factory,
                    plugin_application.action_group_name
                );
                this.email_contexts.set(info, context);
                email.email = context;
            }

            var folder = plugin as Plugin.FolderExtension;
            if (folder != null) {
                folder.folders = new FolderPluginContext(
                    this.controller.application,
                    this.folders_factory,
                    plugin_application.action_group_name
                );
            }

            if (do_activate) {
                var plugin_context = new PluginContext(info, plugin);
                plugin_context.activate.begin((obj, res) => {
                        on_plugin_activated(plugin_context, res);
                    });
            }
        } else {
            warning(
                "Could not construct BasePlugin from %s", info.get_module_name()
            );
        }
    }

    private void on_unload_plugin(Peas.PluginInfo info) {
        var plugin_context = this.plugin_set.get(info);
        if (plugin_context != null) {
            plugin_context.deactivate.begin(
                this.is_shutdown,
                (obj, res) => {
                    on_plugin_deactivated(plugin_context, res);
                }
            );
        }
    }

    private void on_plugin_activated(PluginContext context,
                                     GLib.AsyncResult result) {
        try {
            context.activate.end(result);
            this.plugin_set.set(context.info, context);
            plugin_activated(context.info);
        } catch (GLib.Error err) {
            plugin_error(context.info, err);
            warning(
                "Activating plugin %s threw error, unloading: %s",
                context.info.get_module_name(),
                err.message
            );
            this.plugins.unload_plugin(context.info);
        }
    }

    private void on_plugin_deactivated(PluginContext context,
                                       GLib.AsyncResult result) {
        GLib.Error? error = null;
        try {
            context.deactivate.end(result);
        } catch (GLib.Error err) {
            warning(
                "Deactivating plugin %s threw error: %s",
                context.info.get_module_name(),
                err.message
            );
            error = err;
        }

        var notification = context.plugin as Plugin.NotificationExtension;
        if (notification != null) {
            var notifications = this.notification_contexts.get(context.info);
            if (notifications != null) {
                this.notification_contexts.unset(context.info);
                notifications.destroy();
            }
        }

        var folder = context.plugin as Plugin.FolderExtension;
        if (folder != null) {
            var folder_context = folder.folders as FolderPluginContext;
            if (folder_context != null) {
                folder_context.destroy();
            }
        }

        var email = context.plugin as Plugin.EmailExtension;
        if (email != null) {
            var email_context = email.email as EmailPluginContext;
            if (email_context != null) {
                this.email_contexts.unset(context.info);
                email_context.destroy();
            }
        }

        plugin_deactivated(context.info, error);
        this.plugin_set.unset(context.info);
    }

    private void on_account_available(AccountContext available) {
        add_account(available);
    }

    private void on_account_unavailable(AccountContext unavailable) {
        remove_account(unavailable);
    }

}
