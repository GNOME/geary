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

        private Gee.Map<Geary.Folder,FolderImpl> folders;


        public FolderStoreImpl(Gee.Map<Geary.Folder,FolderImpl> folders) {
            this.folders = folders;
        }

        public Gee.Collection<Plugin.Folder> get_folders() {
            return this.folders.values.read_only_view;
        }

        public Plugin.Folder? get_folder_from_variant(GLib.Variant variant) {
            Plugin.Folder? found = null;
            // XXX this is pretty inefficient
            foreach (var folder in this.folders.values) {
                if (folder.to_variant().equal(variant)) {
                    found = folder;
                    break;
                }
            }
            return found;
        }

        internal void destroy() {
            this.folders = Gee.Map.empty();
        }

    }


    private class AccountImpl : Geary.BaseObject, Plugin.Account {


        public string display_name {
            get { return this.backing.display_name; }
        }


        private Geary.AccountInformation backing;


        public AccountImpl(Geary.AccountInformation backing) {
            this.backing = backing;
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
            get { return this._display_name; }
        }
        private string _display_name;

        public Geary.SpecialFolderType folder_type {
            get { return this.backing.special_folder_type; }
        }

        public Plugin.Account? account {
            get { return this._account; }
        }
        private AccountImpl? _account;

        // The underlying engine folder being represented.
        internal Geary.Folder backing { get; private set; }


        public FolderImpl(Geary.Folder backing, AccountImpl? account) {
            this.backing = backing;
            this._account = account;
            this._persistent_id = ID_FORMAT.printf(
                backing.account.information.id,
                string.join(ID_PATH_SEP, backing.path.as_array())
            );
            folder_type_changed();
        }

        public GLib.Variant to_variant() {
            return new GLib.Variant.tuple({
                    this.backing.account.information.id,
                        new GLib.Variant.variant(this.backing.path.to_variant())
            });
        }

        internal void folder_type_changed() {
            notify_property("folder-type");
            this._display_name = this.backing.get_display_name();
            notify_property("display-name");
        }

    }


    private Client application;
    private Geary.Engine engine;

    private Gee.Map<Geary.AccountInformation,AccountImpl> accounts =
        new Gee.HashMap<Geary.AccountInformation,AccountImpl>();
    private Gee.Map<Geary.Folder,FolderImpl> folders =
        new Gee.HashMap<Geary.Folder,FolderImpl>();
    private Gee.Set<FolderStoreImpl> stores =
        new Gee.HashSet<FolderStoreImpl>();


    /**
     * Constructs a new factory instance.
     */
    public FolderStoreFactory(Client application) throws GLib.Error {
        this.application = application;
        this.engine = application.engine;
        this.engine.account_available.connect(on_account_available);
        this.engine.account_unavailable.connect(on_account_unavailable);
        foreach (Geary.Account account in this.engine.get_accounts()) {
            add_account(account.information);
        }
        application.window_added.connect(on_window_added);
        foreach (MainWindow main in this.application.get_main_windows()) {
            main.notify["selected-folder"].connect(on_folder_selected);
        }
    }

    /** Clearing all state of the store. */
    public void destroy() throws GLib.Error {
        this.application.window_added.disconnect(on_window_added);
        foreach (FolderStoreImpl store in this.stores) {
            store.destroy();
        }
        this.stores.clear();

        this.engine.account_available.disconnect(on_account_available);
        this.engine.account_unavailable.disconnect(on_account_unavailable);
        foreach (Geary.Account account in this.engine.get_accounts()) {
            remove_account(account.information);
        }
        this.folders.clear();
    }

    /** Constructs a new folder store for use by plugin contexts. */
    public Plugin.FolderStore new_folder_store() {
        var store = new FolderStoreImpl(this.folders);
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
    public Plugin.Folder? get_plugin_folder(Geary.Folder engine) {
        return this.folders.get(engine);
    }

    /** Returns the engine folder for the given plugin folder. */
    public Geary.Folder? get_engine_folder(Plugin.Folder plugin) {
        FolderImpl? impl = plugin as FolderImpl;
        return (impl != null) ? impl.backing : null;
    }

    private void add_account(Geary.AccountInformation added) {
        try {
            this.accounts.set(added, new AccountImpl(added));
            Geary.Account account = this.engine.get_account(added);
            account.folders_available_unavailable.connect(
                on_folders_available_unavailable
            );
            account.folders_special_type.connect(
                on_folders_type_changed
            );
            add_folders(account.list_folders());
        } catch (GLib.Error err) {
            warning(
                "Failed to add account %s to folder store: %s",
                added.id, err.message
            );
        }
    }

    private void remove_account(Geary.AccountInformation removed) {
        try {
            Geary.Account account = this.engine.get_account(removed);
            account.folders_available_unavailable.disconnect(
                on_folders_available_unavailable
            );
            account.folders_special_type.disconnect(
                on_folders_type_changed
            );
            remove_folders(account.list_folders());
            this.accounts.unset(removed);
        } catch (GLib.Error err) {
            warning(
                "Error removing account %s from folder store: %s",
                removed.id, err.message
            );
        }
    }

    private void add_folders(Gee.Collection<Geary.Folder> to_add) {
        foreach (Geary.Folder folder in to_add) {
            this.folders.set(
                folder,
                new FolderImpl(
                    folder, this.accounts.get(folder.account.information)
                )
            );
        }
        foreach (FolderStoreImpl store in this.stores) {
            store.folders_available(to_plugin_folders(to_add));
        }
    }

    private void remove_folders(Gee.Collection<Geary.Folder> to_remove) {
        foreach (Geary.Folder folder in to_remove) {
            this.folders.unset(folder);
        }
        foreach (FolderStoreImpl store in this.stores) {
            store.folders_unavailable(to_plugin_folders(to_remove));
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

    private void on_account_available(Geary.AccountInformation to_add) {
        add_account(to_add);
    }

    private void on_account_unavailable(Geary.AccountInformation to_remove) {
        remove_account(to_remove);
    }

    private void on_folders_available_unavailable(
        Geary.Account account,
        Gee.BidirSortedSet<Geary.Folder>? available,
        Gee.BidirSortedSet<Geary.Folder>? unavailable
    ) {
        if (available != null && !available.is_empty) {
            add_folders(available);
        }
        if (unavailable != null && !unavailable.is_empty) {
            remove_folders(unavailable);
        }
    }

    private void on_folders_type_changed(Geary.Account account,
                                         Gee.Collection<Geary.Folder> changed) {
        var folders = to_plugin_folders(changed);
        foreach (FolderImpl folder in folders) {
            folder.folder_type_changed();
        }
        foreach (FolderStoreImpl store in this.stores) {
            store.folders_type_changed(folders);
        }
    }


    private void on_window_added(Gtk.Window window) {
        var main = window as MainWindow;
        if (main != null) {
            main.notify["selected-folder"].connect(on_folder_selected);
        }
    }

    private void on_folder_selected(GLib.Object object, GLib.ParamSpec param) {
        var main = object as MainWindow;
        if (main != null) {
            Geary.Folder? selected = main.selected_folder;
            if (selected != null) {
                var plugin = get_plugin_folder(selected);
                if (plugin != null) {
                    foreach (FolderStoreImpl store in this.stores) {
                        store.folder_selected(plugin);
                    }
                }
            }
        }
    }

}
