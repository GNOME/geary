/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A factory for constructing plugin folder stores and folder objects.
 *
 * This class provides a common implementation that shares folder
 * objects between different plugin context instances.
 */
internal class Application.FolderStoreFactory : Geary.BaseObject {


    private class FolderStoreImpl : Geary.BaseObject, Plugin.FolderStore {


        public override GLib.VariantType folder_variant_type {
            get { return this._folder_variant_type; }
        }
        private GLib.VariantType _folder_variant_type = new GLib.VariantType(
            "(sv)"
        );

        private weak FolderStoreFactory factory;


        public FolderStoreImpl(FolderStoreFactory factory) {
            this.factory = factory;
        }

        public Gee.Collection<Plugin.Folder> get_folders() {
            return this.factory.folders.values.read_only_view;
        }

        public async Gee.Collection<Plugin.Folder> list_containing_folders(
            Plugin.EmailIdentifier target,
            GLib.Cancellable? cancellable
        ) throws GLib.Error {
            var folders = new Gee.LinkedList<Plugin.Folder>();
            var id = target as EmailStoreFactory.IdImpl;
            if (id != null) {
                var context = id.account_impl.backing;
                Gee.MultiMap<Geary.EmailIdentifier,Geary.FolderPath>? multi_folders =
                    yield context.account.get_containing_folders_async(
                        Geary.Collection.single(id.backing),
                        cancellable
                    );
                if (multi_folders != null) {
                    foreach (var path in multi_folders.get(id.backing)) {
                        var folder = context.account.get_folder(path);
                        folders.add(this.factory.folders.get(folder));
                    }
                }
            }
            return folders;
        }

        public async Plugin.Folder create_personal_folder(
            Plugin.Account target,
            string name,
            GLib.Cancellable? cancellable
        ) throws GLib.Error {
            var account = target as PluginManager.AccountImpl;
            if (account == null) {
                throw new Plugin.Error.NOT_SUPPORTED("Invalid account object");
            }
            Geary.Folder engine = yield account.backing.account.create_personal_folder(
                name, NONE, cancellable
            );
            var folder = this.factory.to_plugin_folder(engine);
            if (folder == null) {
                throw new Geary.EngineError.NOT_FOUND(
                    "No plugin folder found for the created folder"
                );
            }
            return folder;
        }

        public Plugin.Folder? get_folder_for_variant(GLib.Variant variant) {
            var folder = this.factory.get_folder_for_variant(variant);
            return this.factory.folders.get(folder);
        }

        internal void destroy() {
            // no-op
        }

    }


    private class FolderImpl : Geary.BaseObject, Plugin.Folder {


        // These constants are used to determine the persistent id of
        // the folder. Changing these may break plugins.
        private const string ID_FORMAT = "%s:%s";
        private const string ID_PATH_SEP = ">";


        public string persistent_id {
            get { return this._persistent_id; }
        }
        private string _persistent_id;

        public string display_name {
            get { return this.backing.display_name; }
        }

        public Geary.Folder.SpecialUse used_as {
            get { return this.backing.folder.used_as; }
        }

        public Plugin.Account? account {
            get { return this._account; }
        }
        private PluginManager.AccountImpl? _account;

        // The underlying folder being represented
        internal FolderContext backing { get; private set; }


        public FolderImpl(FolderContext backing,
                          PluginManager.AccountImpl? account) {
            this.backing = backing;
            this._account = account;
            this._persistent_id = ID_FORMAT.printf(
                account.backing.account.information.id,
                string.join(ID_PATH_SEP, backing.folder.path.as_array())
            );
            folder_type_changed();
        }

        public GLib.Variant to_variant() {
            Geary.Folder folder = this.backing.folder;
            return new GLib.Variant.tuple({
                    folder.account.information.id,
                        new GLib.Variant.variant(folder.path.to_variant())
            });
        }

        internal void folder_type_changed() {
            notify_property("used-as");
            notify_property("display-name");
        }

    }


    private Gee.Map<AccountContext,PluginManager.AccountImpl> accounts;
    private Gee.Map<Geary.Folder,FolderImpl> folders =
        new Gee.HashMap<Geary.Folder,FolderImpl>();
    private Gee.Set<FolderStoreImpl> stores =
        new Gee.HashSet<FolderStoreImpl>();


    /**
     * Constructs a new factory instance.
     */
    public FolderStoreFactory(Gee.Map<AccountContext,PluginManager.AccountImpl> accounts) {
        this.accounts = accounts;
    }

    /** Clearing all state of the store. */
    public void destroy() throws GLib.Error {
        foreach (FolderStoreImpl store in this.stores) {
            store.destroy();
        }
        this.stores.clear();
        this.folders.clear();
    }

    /** Constructs a new folder store for use by plugin contexts. */
    public Plugin.FolderStore new_folder_store() {
        var store = new FolderStoreImpl(this);
        this.stores.add(store);
        return store;
    }

    /** Destroys a folder store once is no longer required. */
    public void destroy_folder_store(Plugin.FolderStore plugin) {
        FolderStoreImpl? impl = plugin as FolderStoreImpl;
        if (impl != null) {
            impl.destroy();
            this.stores.remove(impl);
        }
    }

    /** Returns the plugin folder for the given engine folder. */
    public Plugin.Folder? to_plugin_folder(Geary.Folder engine) {
        return this.folders.get(engine);
    }

    /** Returns the engine folder for the given plugin folder. */
    public Geary.Folder? to_engine_folder(Plugin.Folder plugin) {
        FolderImpl? impl = plugin as FolderImpl;
        return (impl != null) ? impl.backing.folder : null;
    }

    /** Returns the folder context for the given plugin folder. */
    public FolderContext to_folder_context(Plugin.Folder plugin) {
        FolderImpl? impl = plugin as FolderImpl;
        return (impl != null) ? impl.backing : null;
    }

    /** Returns the folder context for the given plugin folder id. */
    public Geary.Folder? get_folder_for_variant(GLib.Variant target) {
        string id = (string) target.get_child_value(0);
        AccountContext? context = null;
        foreach (var key in this.accounts.keys) {
            if (key.account.information.id == id) {
                context = key;
                break;
            }
        }
        Geary.Folder? folder = null;
        if (context != null) {
            try {
                Geary.FolderPath? path = context.account.to_folder_path(
                    target.get_child_value(1).get_variant()
                );
                folder = context.account.get_folder(path);
            } catch (GLib.Error err) {
                debug("Could not find account/folder %s", err.message);
            }
        }
        return folder;
    }

    internal void add_account(AccountContext added) {
        added.folders_available.connect(on_folders_available);
        added.folders_unavailable.connect(on_folders_unavailable);
        added.account.folders_use_changed.connect(on_folders_use_changed);
        var folders = added.get_folders();
        if (!folders.is_empty) {
            add_folders(added, folders);
        }
     }

    internal void remove_account(AccountContext removed) {
        removed.folders_available.disconnect(on_folders_available);
        removed.folders_unavailable.disconnect(on_folders_unavailable);
        removed.account.folders_use_changed.disconnect(on_folders_use_changed);
        var folders = removed.get_folders();
        if (!folders.is_empty) {
            remove_folders(removed, folders);
        }
    }

    internal void main_window_added(MainWindow added) {
        added.notify["selected-folder"].connect(on_folder_selected);
    }

    private void add_folders(AccountContext account,
                             Gee.Collection<FolderContext> to_add) {
        foreach (var context in to_add) {
            this.folders.set(
                context.folder,
                new FolderImpl(context, this.accounts.get(account))
            );
        }
        var folder_impls = Geary.traverse(
            to_add
        ).map<FolderImpl>(
            (context => this.folders.get(context.folder))
        ).to_linked_list().read_only_view;
        foreach (FolderStoreImpl store in this.stores) {
            store.folders_available(folder_impls);
        }
    }

    private void remove_folders(AccountContext account,
                                Gee.Collection<FolderContext> to_remove) {
        var folder_impls = Geary.traverse(
            to_remove
        ).map<FolderImpl>(
            (context => this.folders.get(context.folder))
        ).to_linked_list().read_only_view;
        foreach (FolderStoreImpl store in this.stores) {
            store.folders_unavailable(folder_impls);
        }
        foreach (var context in to_remove) {
            this.folders.unset(context.folder);
        }
    }

    private Gee.Collection<FolderImpl> to_plugin_folders(
        Gee.Collection<Geary.Folder> folders
    ) {
        return Geary.traverse(
            folders
        ).map<FolderImpl>(
            (f) => this.folders.get(f)
        ).to_linked_list().read_only_view;
    }

    private void on_folders_available(AccountContext account,
                                      Gee.Collection<FolderContext> available) {
        add_folders(account, available);
    }

    private void on_folders_unavailable(AccountContext account,
                                        Gee.Collection<FolderContext> unavailable) {
        remove_folders(account, unavailable);
    }

    private void on_folders_use_changed(Geary.Account account,
                                        Gee.Collection<Geary.Folder> changed) {
        var folders = to_plugin_folders(changed);
        foreach (FolderImpl folder in folders) {
            folder.folder_type_changed();
        }
        foreach (FolderStoreImpl store in this.stores) {
            store.folders_type_changed(folders);
        }
    }

    private void on_folder_selected(GLib.Object object, GLib.ParamSpec param) {
        var main = object as MainWindow;
        if (main != null) {
            Geary.Folder? selected = main.selected_folder;
            if (selected != null) {
                var plugin = to_plugin_folder(selected);
                if (plugin != null) {
                    foreach (FolderStoreImpl store in this.stores) {
                        store.folder_selected(plugin);
                    }
                }
            }
        }
    }

}
