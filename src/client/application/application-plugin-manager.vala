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
    // application stats up and hence hidden in the UI. Note that the
    // .plugin files for these should be listed in po/POTFILES.skip,
    // so translators don't need to bother with them.
    private const string[] AUTOLOAD_MODULES = {
        "desktop-notifications",
        "folder-highlight",
        "notification-badge",
        "special-folders",
    };


    /** Aggregates application-wide plugin objects. */
    internal class PluginGlobals {

        public FolderStoreFactory folders { get; private set; }
        public EmailStoreFactory email { get; private set; }
        public Gee.Map<AccountContext,AccountImpl> accounts =
            new Gee.HashMap<AccountContext,AccountImpl>();


        public PluginGlobals(Application.Client application,
                             Application.Controller controller) {
            this.folders = new FolderStoreFactory(this.accounts.read_only_view);
            this.email = new EmailStoreFactory(this.accounts.read_only_view);

            application.window_added.connect(this.on_window_added);
            foreach (MainWindow main in application.get_main_windows()) {
                this.folders.main_window_added(main);
            }

            controller.account_available.connect(this.on_add_account);
            controller.account_unavailable.connect(this.on_remove_account);
            foreach (var context in controller.get_account_contexts()) {
                on_add_account(context);
            }
        }

        public void destroy() throws GLib.Error {
            this.email.destroy();
            this.folders.destroy();
            this.accounts.clear();
        }

        private void on_window_added(Gtk.Window window) {
            var main = window as MainWindow;
            if (main != null) {
                this.folders.main_window_added(main);
            }
        }

        private void on_add_account(AccountContext added) {
            this.accounts.set(added, new AccountImpl(added));
            this.folders.add_account(added);
        }

        private void on_remove_account(AccountContext removed) {
            this.folders.remove_account(removed);
            this.accounts.unset(removed);
        }

    }

    /** Aggregates state specific to a single plugin. */
    internal class PluginContext {


        internal Peas.PluginInfo info { get; private set; }
        internal Plugin.PluginBase instance { get; private set; }
        internal ApplicationImpl application { get; private set; }
        internal string action_group_name { get; private set; }


        internal PluginContext(Peas.Engine engine,
                               Peas.PluginInfo info,
                               Client application,
                               PluginGlobals globals) throws GLib.Error {
            var app_impl = new ApplicationImpl(application, this, globals);
            var instance = engine.create_extension(
                info,
                typeof(Plugin.PluginBase),
                "plugin_application", app_impl
            ) as Plugin.PluginBase;
            if (instance == null) {
                throw new Plugin.Error.NOT_SUPPORTED(
                    "Plugin extension does implement PluginBase"
                );
            }

            this.info = info;
            this.application = app_impl;
            this.instance = instance;
            this.action_group_name = info.get_module_name().replace(".", "-");
        }

        public async void activate(bool is_startup) throws GLib.Error {
            yield this.instance.activate(is_startup);
        }

        public async void deactivate(bool is_shutdown) throws GLib.Error {
            yield this.instance.deactivate(is_shutdown);
        }

    }


    /** A plugin-specific implementation of its Application object. */
    internal class ApplicationImpl : Geary.BaseObject, Plugin.Application {


        internal weak Client backing;
        internal weak PluginContext plugin;
        internal weak PluginGlobals globals;

        private GLib.SimpleActionGroup? action_group = null;
        private Gee.Map<Composer.Widget,ComposerImpl> composer_impls =
        new Gee.HashMap<Composer.Widget,ComposerImpl>();


        public ApplicationImpl(Client backing,
                               PluginContext plugin,
                               PluginGlobals globals) {
            this.backing = backing;
            this.plugin = plugin;
            this.globals = globals;
        }

        public async Plugin.Composer compose_blank(Plugin.Account source)
            throws Plugin.Error {
            var impl = source as AccountImpl;
            if (impl == null) {
                throw new Plugin.Error.NOT_SUPPORTED("Not a valid account");
            }
            return to_plugin_composer(
                yield this.backing.controller.compose_blank(impl.backing)
            );
        }

        public async Plugin.Composer? compose_with_context(
            Plugin.Account send_from,
            Plugin.Composer.ContextType plugin_type,
            Plugin.EmailIdentifier to_load,
            string? quote = null
        ) throws Plugin.Error {
            var source_impl = send_from as AccountImpl;
            if (source_impl == null) {
                throw new Plugin.Error.NOT_SUPPORTED("Not a valid account");
            }
            var id = this.globals.email.to_engine_id(to_load);
            if (id == null) {
                throw new Plugin.Error.NOT_FOUND("Email id not found");
            }
            Gee.Collection<Geary.Email>? email = null;
            try {
                email = yield source_impl.backing.emails.list_email_by_sparse_id_async(
                    Geary.Collection.single(id),
                    Composer.Widget.REQUIRED_FIELDS,
                    NONE,
                    source_impl.backing.cancellable
                );
            } catch (GLib.Error err) {
                throw new Plugin.Error.NOT_FOUND(
                    "Error looking up email: %s", err.message
                );
            }
            if (email == null || email.is_empty) {
                throw new Plugin.Error.NOT_FOUND("Email not found for id");
            }
            var context = Geary.Collection.first(email);

            var type = Composer.Widget.ContextType.NONE;
            switch (plugin_type) {
            case NONE:
                type = Composer.Widget.ContextType.NONE;
                break;

            case EDIT:
                type = Composer.Widget.ContextType.EDIT;
                // Use the same folder that the email exists since it
                // could be getting edited somewhere outside of drafts
                // (e.g. templates)
                break;

            case REPLY_SENDER:
                type = Composer.Widget.ContextType.REPLY_SENDER;
                break;

            case REPLY_ALL:
                type = Composer.Widget.ContextType.REPLY_ALL;
                break;

            case FORWARD:
                type = Composer.Widget.ContextType.FORWARD;
                break;
            }

            return to_plugin_composer(
                yield this.backing.controller.compose_with_context(
                    source_impl.backing,
                    type,
                    context,
                    quote
                )
            );
        }

        public void register_action(GLib.Action action) {
            if (this.action_group == null) {
                this.action_group = new GLib.SimpleActionGroup();
                this.backing.window_added.connect(on_window_added);
                foreach (MainWindow main in this.backing.get_main_windows()) {
                    main.insert_action_group(
                        this.plugin.action_group_name,
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
            Geary.Folder? target = this.globals.folders.to_engine_folder(folder);
            if (target != null) {
                MainWindow window = this.backing.get_active_main_window();
                window.select_folder.begin(target, true);
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

           Geary.Folder? target = this.globals.folders.to_engine_folder(folder);
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

        public void report_problem(Geary.ProblemReport problem) {
            this.backing.controller.report_problem(problem);
        }

        internal void engine_composer_registered(Composer.Widget registered) {
            var impl = to_plugin_composer(registered);
            if (impl != null) {
                composer_registered(impl);
            }
        }

        internal void engine_composer_deregistered(Composer.Widget deregistered) {
            var impl = this.composer_impls.get(deregistered);
            if (impl != null) {
                composer_deregistered(impl);
                this.composer_impls.unset(deregistered);
            }
        }

        private ComposerImpl? to_plugin_composer(Composer.Widget? widget) {
            ComposerImpl impl = null;
            if (widget != null) {
                impl = this.composer_impls.get(widget);
                if (impl == null) {
                    impl = new ComposerImpl(widget, this);
                    this.composer_impls.set(widget, impl);
                }
            }
            return impl;
        }

        private void on_window_added(Gtk.Window window) {
            if (this.action_group != null) {
                var main = window as MainWindow;
                if (main != null) {
                    main.insert_action_group(
                        this.plugin.action_group_name,
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


    /** An implementation of the plugin Composer interface. */
    internal class ComposerImpl : Geary.BaseObject, Plugin.Composer {


        public bool can_send { get; set; default = false; }

        public Plugin.Account? sender_context {
            get {
                // ugh
                this._sender_context = this.application.globals.accounts.get(
                    this.backing.sender_context
                );
                return this._sender_context;
            }
        }
        private Plugin.Account? _sender_context = null;

        public string action_group_name {
            get { return this._action_group_name; }
        }
        private string _action_group_name;

        public Plugin.Folder? save_to  {
            get {
                // Ugh
                this._save_to = (
                    (backing.save_to != null)
                    ? this.application.globals.folders.to_plugin_folder(
                        this.backing.save_to
                    )
                    : null
                );
                return this._save_to;
            }
        }
        private Plugin.Folder? _save_to = null;

        private Composer.Widget backing;
        private weak ApplicationImpl application;
        private GLib.SimpleActionGroup? action_group = null;
        private GLib.Menu? menu_items = null;
        private Gtk.ActionBar? action_bar = null;


        public ComposerImpl(Composer.Widget backing,
                            ApplicationImpl application) {
            this.backing = backing;
            this.application = application;
            this._action_group_name = application.plugin.action_group_name + "-cmp";
            backing.bind_property(
                "can-send",
                this,
                "can-send",
                BindingFlags.SYNC_CREATE |
                BindingFlags.BIDIRECTIONAL);
        }

        public void save_to_folder(Plugin.Folder? location) {
            var engine = this.application.globals.folders.to_engine_folder(location);
            if (engine != null && engine.account == this.backing.sender_context.account) {
                this.backing.set_save_to_override(engine);
            }
        }

        public void present() {
            this.application.backing.controller.present_composer(this.backing);
        }

        public void insert_text(string plain_text) {
            var entry = this.backing.focused_input_widget as Gtk.Entry;
            if (entry != null) {
                entry.insert_at_cursor(plain_text);
            } else {
                this.backing.editor.body.insert_text(plain_text);
            }
        }

        public void register_action(GLib.Action action) {
            if (this.action_group == null) {
                this.action_group = new GLib.SimpleActionGroup();
                this.backing.insert_action_group(
                    this.action_group_name,
                    this.action_group
                );
            }

            this.action_group.add_action(action);
        }

        public void deregister_action(GLib.Action action) {
            this.action_group.remove_action(action.get_name());
        }

        public void append_menu_item(Plugin.Actionable menu_item) {
            if (this.menu_items == null) {
                this.menu_items = new GLib.Menu();
                this.backing.editor.insert_menu_section(this.menu_items);
            }
            this.menu_items.append(
                menu_item.label,
                GLib.Action.print_detailed_name(
                    this.action_group_name + "." + menu_item.action.name,
                    menu_item.action_target
                )
            );
        }

        public void set_action_bar(Plugin.ActionBar plugin_bar) {
            if (this.action_bar != null) {
                this.action_bar.hide();
                this.action_bar.destroy();
                this.action_bar = null;
            }

            this.action_bar = new Gtk.ActionBar();
            Gtk.Box? centre = null;
            foreach (var pos in new Plugin.ActionBar.Position[] { START, CENTRE, END}) {
                foreach (var item in plugin_bar.get_items(pos)) {
                    var widget = widget_for_item(item);
                    switch (pos) {
                    case START:
                        this.action_bar.pack_start(widget);
                        break;

                    case CENTRE:
                        if (centre == null) {
                            centre = new Gtk.Box(HORIZONTAL, 0);
                            this.action_bar.set_center_widget(centre);
                        }
                        centre.add(widget);
                        break;

                    case END:
                        this.action_bar.pack_end(widget);
                        break;
                    }
                }
            }

            this.action_bar.show_all();
            this.backing.editor.add_action_bar(this.action_bar);
        }

        private Gtk.Widget? widget_for_item(Plugin.ActionBar.Item item) {
            var item_type = item.get_type();
            if (item_type == typeof(Plugin.ActionBar.LabelItem)) {
                var label = new Gtk.Label(
                    ((Plugin.ActionBar.LabelItem) item).text
                );
                return label;
            }
            if (item_type == typeof(Plugin.ActionBar.ButtonItem)) {
                var button_item = item as Plugin.ActionBar.ButtonItem;
                var button = new Gtk.Button.with_label(button_item.action.label);
                button.set_action_name(
                    this.action_group_name + "." + button_item.action.action.name
                );
                if (button_item.action.action_target != null) {
                    button.set_action_target_value(button_item.action.action_target);
                }
                return button;
            }
            if (item_type == typeof(Plugin.ActionBar.MenuItem)) {
                var menu_item = item as Plugin.ActionBar.MenuItem;

                var label = new Gtk.Box(HORIZONTAL, 6);
                label.add(new Gtk.Label(menu_item.label));
                label.add(new Gtk.Image.from_icon_name(
                    "pan-up-symbolic", Gtk.IconSize.BUTTON
                ));

                var button = new Gtk.MenuButton();
                button.direction = Gtk.ArrowType.UP;
                button.use_popover = true;
                button.menu_model = menu_item.menu;
                button.add(label);

                return button;
            }
            if (item_type == typeof(Plugin.ActionBar.GroupItem)) {
                var group_items = item as Plugin.ActionBar.GroupItem;
                var box = new Gtk.Box(HORIZONTAL, 0);
                box.get_style_context().add_class(Gtk.STYLE_CLASS_LINKED);
                foreach (var group_item in group_items.get_items()) {
                    box.add(widget_for_item(group_item));
                }
                return box;
            }

            return null;
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


    internal PluginGlobals globals { get; private set; }


    private weak Client application;
    private weak Controller controller;
    private Configuration config;
    private Peas.Engine plugin_engine;
    private bool is_startup = true;
    private bool is_shutdown = false;
    private string trusted_path;

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
        this.globals = new PluginGlobals(application, controller);
        this.plugin_engine = Peas.Engine.get_default();

        this.trusted_path = trusted_plugin_path.get_path();
        this.plugin_engine.add_search_path(this.trusted_path, null);

        this.plugin_engine.load_plugin.connect_after(on_load_plugin);
        this.plugin_engine.unload_plugin.connect(on_unload_plugin);

        controller.composer_registered.connect(this.on_composer_registered);
        controller.composer_deregistered.connect(this.on_composer_deregistered);

        string[] optional_names = this.config.get_optional_plugins();
        foreach (Peas.PluginInfo info in this.plugin_engine.get_plugin_list()) {
            string name = info.get_module_name();
            try {
                if (info.is_available()) {
                    if (is_autoload(info)) {
                        debug("Loading autoload plugin: %s", name);
                        this.plugin_engine.load_plugin(info);
                    } else if (name in optional_names) {
                        debug("Loading optional plugin: %s", name);
                        this.plugin_engine.load_plugin(info);
                    }
                }
            } catch (GLib.Error err) {
                warning("Plugin %s not available: %s", name, err.message);
            }
        }

        this.is_startup = false;
    }

    /** Returns the client account context for the given plugin account, if any. */
    public AccountContext? to_client_account(Plugin.Account plugin) {
        var impl = plugin as AccountImpl;
        return (impl != null) ? impl.backing : null;
    }

    /** Returns the engine account for the given plugin account, if any. */
    public Geary.Account? to_engine_account(Plugin.Account plugin) {
        var impl = plugin as AccountImpl;
        return (impl != null) ? impl.backing.account : null;
    }

    /** Returns the engine folder for the given plugin folder, if any. */
    public Geary.Folder? to_engine_folder(Plugin.Folder plugin) {
        return this.globals.folders.to_engine_folder(plugin);
    }

    /** Returns the engine email for the given plugin email, if any. */
    public Geary.Email? to_engine_email(Plugin.Email plugin) {
        return this.globals.email.to_engine_email(plugin);
    }

    public Gee.Collection<Peas.PluginInfo> get_optional_plugins() {
        var plugins = new Gee.LinkedList<Peas.PluginInfo>();
        foreach (Peas.PluginInfo plugin in this.plugin_engine.get_plugin_list()) {
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
            this.plugin_engine.load_plugin(plugin);
            loaded = true;
        }
        return loaded;
    }

    public bool unload_optional(Peas.PluginInfo plugin) throws GLib.Error {
        bool unloaded = false;
        if (plugin.is_available() &&
            plugin.is_loaded() &&
            !is_autoload(plugin)) {
            this.plugin_engine.unload_plugin(plugin);
            unloaded = true;
        }
        return unloaded;
    }

    internal void close() throws GLib.Error {
        this.is_shutdown = true;
        this.plugin_engine.set_loaded_plugins(null);
        this.plugin_engine.garbage_collect();
        this.globals.destroy();
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

    private void on_load_plugin(Peas.PluginInfo info) {
        PluginContext? context = null;
        try {
            context = new PluginContext(
                this.plugin_engine,
                info,
                this.application,
                this.globals
            );
        } catch (GLib.Error err) {
            debug("Failed to create new plugin instance: %s", err.message);
        }
        if (context != null) {
            bool do_activate = true;
            var trusted = context.instance as Plugin.TrustedExtension;
            if (trusted != null) {
                if (info.get_module_dir().has_prefix(this.trusted_path)) {
                    trusted.client_application = this.application;
                    trusted.client_plugins = this;
                } else {
                    do_activate = false;
                    this.plugin_engine.unload_plugin(info);
                }
            }

            var notification = context.instance as Plugin.NotificationExtension;
            if (notification != null) {
                var notification_context = new NotificationPluginContext(
                    this.application,
                    this.globals,
                    context
                );
                this.notification_contexts.set(info, notification_context);
                notification.notifications = notification_context;
            }

            var email = context.instance as Plugin.EmailExtension;
            if (email != null) {
                var email_context = new EmailPluginContext(
                    this.application,
                    this.globals,
                    context
                );
                this.email_contexts.set(info, email_context);
                email.email = email_context;
            }

            var folder = context.instance as Plugin.FolderExtension;
            if (folder != null) {
                folder.folders = new FolderPluginContext(
                    this.controller.application,
                    this.globals,
                    context
                );
            }

            if (do_activate) {
                context.activate.begin(
                    this.is_startup,
                    (obj, res) => { on_plugin_activated(context, res); }
                );
            }
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

            // Update config here for optional plugins so we catch
            // and add dependencies being loaded
            if (!is_autoload(context.info)) {
                string name = context.info.get_module_name();
                string[] optional = this.config.get_optional_plugins();
                if (!(name in optional)) {
                    optional += name;
                    this.config.set_optional_plugins(optional);
                }
            }
        } catch (GLib.Error err) {
            plugin_error(context.info, err);
            warning(
                "Activating plugin %s threw error, unloading: %s",
                context.info.get_module_name(),
                err.message
            );
            this.plugin_engine.unload_plugin(context.info);
        }
    }

    private void on_plugin_deactivated(PluginContext context,
                                       GLib.AsyncResult result) {
        if (!is_autoload(context.info) && !this.is_shutdown) {
            // Update config here for optional plugins so we catch
            // and remove dependencies being unloaded, too
            string name = context.info.get_module_name();
            string[] old_names = this.config.get_optional_plugins();
            string[] new_names = new string[0];
            for (int i = 0; i < old_names.length; i++) {
                if (old_names[i] != name) {
                    new_names += old_names[i];
                }
            }
            this.config.set_optional_plugins(new_names);
        }

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

        var notification = context.instance as Plugin.NotificationExtension;
        if (notification != null) {
            var notifications = this.notification_contexts.get(context.info);
            if (notifications != null) {
                this.notification_contexts.unset(context.info);
                notifications.destroy();
            }
        }

        var folder = context.instance as Plugin.FolderExtension;
        if (folder != null) {
            var folder_context = folder.folders as FolderPluginContext;
            if (folder_context != null) {
                folder_context.destroy();
            }
        }

        var email = context.instance as Plugin.EmailExtension;
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

    private void on_composer_registered(Composer.Widget registered) {
        foreach (var context in this.plugin_set.values) {
            context.application.engine_composer_registered(registered);
        }
    }

    private void on_composer_deregistered(Composer.Widget deregistered) {
        foreach (var context in this.plugin_set.values) {
            context.application.engine_composer_deregistered(deregistered);
        }
    }

}
