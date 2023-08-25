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
public class Plugin.SpecialFolders :
    PluginBase, FolderExtension, EmailExtension {


    private const string ACTION_EDIT = "edit-draft";
    private const string ACTION_EMPTY = "empty-folder";

    // InfoBar priority
    private const int PRIORITY = 10;


    public FolderContext folders {
        get; set construct;
    }

    public EmailContext email {
        get; set construct;
    }


    private EmailStore? email_store = null;
    private FolderStore? folder_store = null;

    private Gee.Map<Folder,InfoBar> info_bars =
        new Gee.HashMap<Folder,InfoBar>();

    private GLib.SimpleAction? edit_action = null;
    private GLib.SimpleAction? empty_action = null;

    private GLib.Cancellable cancellable = new GLib.Cancellable();


    public override async void activate(bool is_startup) throws GLib.Error {
        this.email_store = yield this.email.get_email_store();
        this.email_store.email_displayed.connect(on_email_displayed);

        this.folder_store = yield this.folders.get_folder_store();
        this.folder_store.folder_selected.connect(on_folder_selected);
        this.folder_store.folders_type_changed.connect(on_folders_type_changed);

        this.edit_action = new GLib.SimpleAction(
            ACTION_EDIT, this.email_store.email_identifier_variant_type
        );
        this.edit_action.activate.connect(on_edit_activated);
        this.plugin_application.register_action(this.edit_action);

        this.empty_action = new GLib.SimpleAction(
            ACTION_EMPTY, this.folder_store.folder_variant_type
        );
        this.empty_action.activate.connect(on_empty_activated);
        this.plugin_application.register_action(this.empty_action);
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.plugin_application.deregister_action(this.edit_action);
        this.edit_action = null;

        this.plugin_application.deregister_action(this.empty_action);
        this.empty_action = null;

        this.email_store.email_displayed.disconnect(on_email_displayed);
        this.email_store = null;

        this.folder_store.folder_selected.disconnect(on_folder_selected);
        this.folder_store.folders_type_changed.disconnect(on_folders_type_changed);
        this.folder_store = null;

        this.cancellable.cancel();
    }

    private void update_folder(Folder target) {
        switch (target.used_as) {
        case TRASH:
            this.folders.add_folder_info_bar(
                target, get_folder_info_bar(target), PRIORITY
            );
            break;

        case JUNK:
            this.folders.add_folder_info_bar(
                target, get_folder_info_bar(target), PRIORITY
            );
            break;

        default:
            // no-op
            break;
        }
    }

    private async void update_email(Email target) {
        bool is_draft = false;
        if (target.flags.is_draft()) {
            is_draft = true;
        } else if (this.folder_store != null) {
            try {
                Gee.Collection<Folder> folders = yield
                this.folder_store.list_containing_folders(
                    target.identifier, this.cancellable
                );
                foreach (var folder in folders) {
                    if (folder.used_as == DRAFTS) {
                        is_draft = true;
                        break;
                    }
                }
            } catch (GLib.Error err) {
                warning("Could not list containing folders for email");
            }
        }
        if (is_draft) {
            this.email.add_email_info_bar(
                target.identifier,
                new_draft_info_bar(target),
                PRIORITY
            );
        }

        if (target.flags.is_outbox_sent()) {
            this.email.add_email_info_bar(
                target.identifier,
                new_unsaved_info_bar(target),
                PRIORITY
            );
        }
    }

    private async void edit_draft(EmailIdentifier id) {
        try {
            var composer = yield this.plugin_application.compose_with_context(
                id.account,
                Composer.ContextType.EDIT,
                id
            );
            composer.present();
        } catch (GLib.Error err) {
            warning("Unable to construct composer: %s", err.message);
        }
    }

    private InfoBar get_folder_info_bar(Folder target) {
        var bar = this.info_bars.get(target);
        if (bar == null) {
            bar = new InfoBar(target.display_name);
            bar.primary_button = new Actionable(
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

    private InfoBar new_draft_info_bar(Email target) {
        var bar = new InfoBar(
            // Translators: Info bar status message for a draft email
            _("Draft message"),
            // Translators: Info bar status description for a draft
            // email
            _("This message has not yet been sent.")
        );
        bar.primary_button = new Actionable(
            // Translators: Info bar button label for editing a draft
            // email
            _("Edit"),
            this.edit_action,
            target.identifier.to_variant()
        );
        return bar;
    }

    private InfoBar new_unsaved_info_bar(Email target) {
        return new InfoBar(
            // Translators: Info bar status message for an sent but
            // unsaved email
            _("Message not saved"),
            // Translators: Info bar status description for a sent but
            // unsaved email
            _("This message was sent, but has not been saved to your account.")
        );
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

    private void on_edit_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id = this.email_store.get_email_identifier_for_variant(
                target
            );
            if (id != null) {
                this.edit_draft.begin(id);
            } else {
                warning("Bad draft id");
            }
        }
    }

    private void on_empty_activated(GLib.Action action, GLib.Variant? target) {
        if (this.folder_store != null && target != null) {
            Folder? folder = this.folder_store.get_folder_for_variant(target);
            if (folder != null) {
                this.plugin_application.empty_folder.begin(folder);
            }
        }
    }

    private void on_email_displayed(Email email) {
        update_email.begin(email);
    }

}
