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
        typeof(Plugin.EmailTemplates)
    );
}

/**
 * Enables editing and sending email templates.
 */
public class Plugin.EmailTemplates :
    PluginBase, FolderExtension, EmailExtension {


    // Translators: Templates folder name alternatives. Separate names
    // using a vertical bar and put the most common localized name to
    // the front for the default. English names do not need to be
    // included.
    private const string LOC_NAMES = _(
        "Templates | Template Mail | Template Email | Template E-Mail"
    );
    // This must be identical to he above except without translation
    private const string UNLOC_NAMES = (
        "Templates | Template Mail | Template Email | Template E-Mail"
    );


    private const string ACTION_NEW = "new-template";
    private const string ACTION_EDIT = "edit-template";
    private const string ACTION_SEND = "send-template";

    private const int INFO_BAR_PRIORITY = 0;


    public FolderContext folders {
        get; set construct;
    }

    public EmailContext email {
        get; set construct;
    }


    private FolderStore? folder_store = null;
    private EmailStore? email_store = null;

    private GLib.SimpleAction? new_action = null;
    private GLib.SimpleAction? edit_action = null;
    private GLib.SimpleAction? send_action = null;

    private Gee.Map<Folder,InfoBar> info_bars =
        new Gee.HashMap<Folder,InfoBar>();

    private Gee.List<string> folder_names = new Gee.ArrayList<string>();

    private GLib.Cancellable cancellable = new GLib.Cancellable();


    public override async void activate(bool is_startup) throws GLib.Error {
        // Add localised first, so if we need to create a folder it
        // will be created localised.
        Geary.iterate_array(LOC_NAMES.split("|")).map<string>(
            (name) => name.strip()
        ).add_all_to(this.folder_names);
        Geary.iterate_array(UNLOC_NAMES.split("|")).map<string>(
            (name) => name.strip()
        ).add_all_to(this.folder_names);

        this.folder_store = yield this.folders.get_folder_store();
        this.folder_store.folders_available.connect(on_folders_available);
        this.folder_store.folders_unavailable.connect(on_folders_unavailable);
        this.folder_store.folders_type_changed.connect(on_folders_type_changed);
        this.folder_store.folder_selected.connect(on_folder_selected);

        this.email_store = yield this.email.get_email_store();
        this.email_store.email_displayed.connect(on_email_displayed);

        this.new_action = new GLib.SimpleAction(
            ACTION_NEW, this.folder_store.folder_variant_type
        );
        this.new_action.activate.connect(on_new_activated);
        this.plugin_application.register_action(this.new_action);

        this.edit_action = new GLib.SimpleAction(
            ACTION_EDIT, this.email_store.email_identifier_variant_type
        );
        this.edit_action.activate.connect(on_edit_activated);
        this.plugin_application.register_action(this.edit_action);

        this.send_action = new GLib.SimpleAction(
            ACTION_SEND, this.email_store.email_identifier_variant_type
        );
        this.send_action.activate.connect(on_send_activated);
        this.plugin_application.register_action(this.send_action);

        add_folders(this.folder_store.get_folders());
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.cancellable.cancel();

        // Take a copy of the keys so the collection doesn't asplode
        // as it is being modified.
        foreach (var folder in this.info_bars.keys.to_array()) {
            unregister_folder(folder);
        }
        this.info_bars.clear();
        this.folder_names.clear();

        this.plugin_application.deregister_action(this.new_action);
        this.new_action = null;

        this.plugin_application.deregister_action(this.edit_action);
        this.edit_action = null;

        this.plugin_application.deregister_action(this.send_action);
        this.send_action = null;

        this.folder_store.folders_available.disconnect(on_folders_available);
        this.folder_store.folders_unavailable.disconnect(on_folders_unavailable);
        this.folder_store.folders_type_changed.disconnect(on_folders_type_changed);
        this.folder_store.folder_selected.disconnect(on_folder_selected);
        this.folder_store = null;

        this.email_store.email_displayed.disconnect(on_email_displayed);
        this.email_store = null;
    }

    private async void edit_email(Folder? target, EmailIdentifier? id, bool send) {
        var account = (target != null) ? target.account : id.account;
        try {
            Plugin.Composer? composer = null;
            if (id != null) {
                composer = yield this.plugin_application.compose_with_context(
                    id.account,
                    Composer.ContextType.EDIT,
                    id
                );
            } else {
                composer = yield this.plugin_application.compose_blank(account);
            }
            if (!send) {
                var folder = target;
                if (folder == null && id != null) {
                    var containing = yield this.folder_store.list_containing_folders(
                        id, this.cancellable
                    );
                    folder = containing.first_match(
                        (f) => this.info_bars.has_key(f)
                    );
                }
                composer.save_to_folder(folder);
                composer.can_send = false;
            }

            composer.present();
        } catch (GLib.Error err) {
            warning("Unable to construct composer: %s", err.message);
        }
    }

    private void add_folders(Gee.Collection<Folder> to_add) {
        Folder? inbox = null;
        var found_templates = false;
        foreach (var folder in to_add) {
            if (folder.used_as == INBOX) {
                inbox = folder;
            } else if (folder.display_name in this.folder_names) {
                register_folder(folder);
                found_templates = true;
            }
        }

        // XXX There is no way at the moment to determine when all
        // local folders have been loaded, but since they are all done
        // in once batch, it's a safe bet that if we've seen the
        // Inbox, then the local folder set should contain a templates
        // folder, if one is available. If there isn't, we need to
        // create it.
        if (!found_templates && inbox != null) {
            debug("Creating templates folder");
            this.create_folder.begin(inbox.account);
        }
    }

    private void register_folder(Folder target) {
        try {
            this.folders.register_folder_used_as(
                target,
                // Translators: The name of the folder used to
                // store email templates
                _("Templates"),
                "folder-templates-symbolic"
            );
            this.info_bars.set(
                target,
                new_templates_folder_info_bar(target)
            );
        } catch (GLib.Error err) {
            warning(
                "Failed to register %s as templates folder: %s",
                target.persistent_id,
                err.message
            );
        }
    }

    private void unregister_folder(Folder target) {
        var info_bar = this.info_bars.get(target);
        if (info_bar != null) {
            try {
                this.folders.unregister_folder_used_as(target);
            } catch (GLib.Error err) {
                warning(
                    "Failed to unregister %s as templates folder: %s",
                    target.persistent_id,
                    err.message
                );
            }
            this.folders.remove_folder_info_bar(target, info_bar);
            this.info_bars.unset(target);
        }
    }

    private async void create_folder(Account account) {
        try {
            yield this.folder_store.create_personal_folder(
                account,
                this.folder_names[0],
                this.cancellable
            );
            // Don't need to explicitly register the folder here, it
            // will get picked up via the available signal
        } catch (GLib.Error err) {
            warning("Failed to create templates folder: %s", err.message);
        }
    }

    private void update_folder(Folder target) {
        var info_bar = this.info_bars.get(target);
        if (info_bar != null) {
            this.folders.add_folder_info_bar(
                target, info_bar, INFO_BAR_PRIORITY
            );
        }
    }

    private async void update_email(Email target) {
        var containing = Gee.Collection.empty<Folder>();
        try {
            containing = yield this.folder_store.list_containing_folders(
                target.identifier, this.cancellable
            );
        } catch (GLib.Error err) {
            warning("Could not load folders for email: %s", err.message);
        }
        if (containing.any_match((f) => this.info_bars.has_key(f))) {
            this.email.add_email_info_bar(
                target.identifier,
                new_template_email_info_bar(target.identifier),
                INFO_BAR_PRIORITY
            );
        }
    }

    private InfoBar new_templates_folder_info_bar(Folder target) {
        var bar = this.info_bars.get(target);
        if (bar == null) {
            bar = new InfoBar(target.display_name);
            bar.primary_button = new Actionable(
                // Translators: Info bar button label for creating a
                // new email template
                _("New"),
                this.new_action,
                target.to_variant()
            );
            this.info_bars.set(target, bar);
        }
        return bar;
    }

    private InfoBar new_template_email_info_bar(EmailIdentifier target) {
        // Translators: Infobar status label for an email template
        var bar = new InfoBar(_("Message template"));
        bar.primary_button = new Actionable(
            // Translators: Info bar button label for sending an
            // email template
            _("Send"),
            this.send_action,
            target.to_variant()
        );
        bar.secondary_buttons.add(
            new Actionable(
                // Translators: Info bar button label for editing an
                // existing email template
                _("Edit"),
                this.edit_action,
                target.to_variant()
            )
        );
        return bar;
    }

    private void on_folders_available(Gee.Collection<Folder> available) {
        add_folders(available);
    }

    private void on_folders_unavailable(Gee.Collection<Folder> unavailable) {
        foreach (var folder in unavailable) {
            unregister_folder(folder);
        }
    }

    private void on_folders_type_changed(Gee.Collection<Folder> changed) {
        foreach (var folder in changed) {
            unregister_folder(folder);
            if (folder.display_name in this.folder_names) {
                register_folder(folder);
            }
            update_folder(folder);
        }
    }

    private void on_folder_selected(Folder selected) {
        update_folder(selected);
    }

    private void on_new_activated(GLib.Action action, GLib.Variant? target) {
        if (this.folder_store != null && target != null) {
            Folder? folder = this.folder_store.get_folder_for_variant(target);
            if (folder != null) {
                this.edit_email.begin(folder, null, false);
            }
        }
    }

    private void on_edit_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id =
                this.email_store.get_email_identifier_for_variant(target);
            if (id != null) {
                this.edit_email.begin(null, id, false);
            }
        }
    }

    private void on_send_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id =
                this.email_store.get_email_identifier_for_variant(target);
            if (id != null) {
                this.edit_email.begin(null, id, true);
            }
        }
    }

    private void on_email_displayed(Email email) {
        this.update_email.begin(email);
    }

}
