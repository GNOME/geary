/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

[ModuleInit]
public void peas_register_types(TypeModule module) {
    Peas.ObjectModule obj = module as Peas.ObjectModule;
    obj.register_extension_type(
        typeof(Plugin.PluginBase),
        typeof(Plugin.SpecialFolders)
    );
}

/**
 * Manages UI for special folders.
 */
public class Plugin.SpecialFolders : PluginBase, FolderExtension {


    // InfoBar button action name
    private const string ACTION_NAME = "empty-folder";

    // InfoBar priority
    private const int PRIORITY = 0;


    public FolderContext folders {
        get; set construct;
    }


    private FolderStore? store = null;
    private GLib.SimpleAction? empty_action = null;

    private Gee.Map<Folder,InfoBar> info_bars =
        new Gee.HashMap<Folder,InfoBar>();


    public override async void activate() throws GLib.Error {
        this.store = yield this.folders.get_folders();
        this.store.folder_selected.connect(on_folder_selected);
        this.store.folders_type_changed.connect(on_folders_type_changed);

        this.empty_action = new GLib.SimpleAction(
            ACTION_NAME, store.folder_variant_type
        );
        this.empty_action.activate.connect(on_empty_activated);

        this.plugin_application.register_action(this.empty_action);
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.plugin_application.deregister_action(this.empty_action);

        this.empty_action.activate.disconnect(on_empty_activated);
        this.empty_action = null;

        this.store.folder_selected.disconnect(on_folder_selected);
        this.store.folders_type_changed.disconnect(on_folders_type_changed);
        this.store = null;
    }

    private void update_folder(Folder target) {
        switch (target.folder_type) {
        case TRASH:
            this.folders.add_folder_info_bar(
                target, get_info_bar(target), PRIORITY
            );
            break;

        case SPAM:
            this.folders.add_folder_info_bar(
                target, get_info_bar(target), PRIORITY
            );
            break;
        }
    }

    private InfoBar get_info_bar(Folder target) {
        var bar = this.info_bars.get(target);
        if (bar == null) {
            bar = new InfoBar(target.folder_type.get_display_name());
            debug("XXXX folder variant type: %s", target.to_variant().get_type_string());
            bar.primary_button = new Button(
                // Translators: Info bar button label for emptying
                // trash/spam folders
                _("Empty"),
                this.empty_action,
                target.to_variant()
            );
            this.info_bars.set(target, bar);
        }
        return bar;
    }

    private void on_folder_selected(Folder selected) {
        update_folder(selected);
    }

    private void on_folders_type_changed(Gee.Collection<Folder> changed) {
        foreach (var folder in changed) {
            var existing = this.info_bars.get(folder);
            if (existing != null) {
                this.folders.remove_folder_info_bar(folder, existing);
                this.info_bars.unset(folder);
            }
            update_folder(folder);
        }
    }

    private void on_empty_activated(GLib.Action action, GLib.Variant? target) {
        if (this.store != null && target != null) {
            Folder? folder = this.store.get_folder_from_variant(target);
            if (folder != null) {
                this.plugin_application.empty_folder.begin(folder);
            }
        }
    }

}
