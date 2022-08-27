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
        typeof(Plugin.MailMerge)
    );
}

/**
 * Plugin to fill in and send email templates using a spreadsheet.
 */
public class Plugin.MailMerge :
    PluginBase, FolderExtension, EmailExtension, TrustedExtension {


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


    private const string ACTION_EDIT = "edit-template";
    private const string ACTION_INSERT_FIELD = "insert-field";
    private const string ACTION_MERGE = "merge-template";
    private const string ACTION_LOAD = "load-merge-data";
    private const string ACTION_START = "start-send";
    private const string ACTION_PAUSE = "pause-send";

    private const int INFO_BAR_PRIORITY = 10;


    public FolderContext folders {
        get; set construct;
    }

    public EmailContext email {
        get; set construct;
    }

    public global::Application.Client client_application {
        get; set construct;
    }

    public global::Application.PluginManager client_plugins {
        get; set construct;
    }

    private FolderStore? folder_store = null;
    private EmailStore? email_store = null;

    private global::MailMerge.Folder? merge_folder = null;
    private InfoBar merge_bar = null;

    private GLib.SimpleAction? edit_action = null;
    private GLib.SimpleAction? merge_action = null;
    private GLib.SimpleAction? start_action = null;
    private GLib.SimpleAction? pause_action = null;

    private Actionable? start_ui = null;
    private Actionable? pause_ui = null;

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
        this.folder_store.folder_selected.connect(on_folder_selected);

        this.email_store = yield this.email.get_email_store();
        this.email_store.email_displayed.connect(on_email_displayed);

        this.edit_action = new GLib.SimpleAction(
            ACTION_EDIT, this.email_store.email_identifier_variant_type
        );
        this.edit_action.activate.connect(on_edit_activated);
        this.plugin_application.register_action(this.edit_action);

        this.merge_action = new GLib.SimpleAction(
            ACTION_MERGE, this.email_store.email_identifier_variant_type
        );
        this.merge_action.activate.connect(on_merge_activated);
        this.plugin_application.register_action(this.merge_action);

        this.start_action = new GLib.SimpleAction(ACTION_START, null);
        this.start_action.activate.connect(on_start_activated);
        this.plugin_application.register_action(this.start_action);

        this.start_ui = new Actionable.with_icon(
            // Translators: Info bar label for starting sending a mail
            // merge
            _("Start"),
            "media-playback-start-symbolic",
            this.start_action
        );

        this.pause_action = new GLib.SimpleAction(ACTION_PAUSE, null);
        this.pause_action.activate.connect(on_pause_activated);
        this.plugin_application.register_action(this.pause_action);

        this.pause_ui = new Actionable.with_icon(
            // Translators: Info bar label for pausing sending a mail
            // merge
            _("Pause"),
            "media-playback-pause-symbolic",
            this.pause_action
        );

        this.plugin_application.composer_registered.connect(
            this.on_composer_registered
        );
    }

    public override async void deactivate(bool is_shutdown) throws GLib.Error {
        this.cancellable.cancel();

        this.plugin_application.deregister_action(this.edit_action);
        this.edit_action = null;

        this.plugin_application.deregister_action(this.merge_action);
        this.merge_action = null;

        this.folder_store = null;

        this.email_store.email_displayed.disconnect(on_email_displayed);
        this.email_store = null;

        this.folder_names.clear();
    }

    private async void edit_email(EmailIdentifier id) {
        try {
            var composer = yield this.plugin_application.compose_with_context(
                id.account,
                Composer.ContextType.EDIT,
                id
            );
            var containing = yield this.folder_store.list_containing_folders(
                id, this.cancellable
            );
            var folder = containing.first_match(
                (f) => f.display_name in this.folder_names
            );

            composer.save_to_folder(folder);
            composer.can_send = false;
            composer.present();
        } catch (GLib.Error err) {
            warning("Unable to construct composer: %s", err.message);
        }
    }

    private async void merge_email(EmailIdentifier id,
                                   GLib.File? default_csv_file) {
        var csv_file = default_csv_file ?? show_merge_data_chooser();
        if (csv_file != null) {
            try {
                var csv_input = yield csv_file.read_async(
                    GLib.Priority.DEFAULT,
                    this.cancellable
                );
                var csv = yield new global::MailMerge.Csv.Reader(
                    csv_input, this.cancellable
                );

                Gee.Collection<Email> emails = yield this.email_store.get_email(
                    Geary.Collection.single(id),
                    this.cancellable
                );
                if (!emails.is_empty) {
                    var account_context = this.client_plugins.to_client_account(
                        id.account
                    );
                    var email = Geary.Collection.first(emails);

                    this.merge_folder = yield new global::MailMerge.Folder(
                        account_context.account,
                        account_context.account.local_folder_root,
                        yield load_merge_email(email),
                        csv_file,
                        csv
                    );

                    this.merge_bar = new InfoBar(
                        this.merge_folder.data_display_name, ""
                    );
                    update_merge_folder_info_bar();
                    this.merge_bar.show_close_button = true;
                    this.merge_bar.close_activated.connect(on_merge_closed);
                    this.merge_folder.notify["email-sent"].connect(
                        () => { update_merge_folder_info_bar(); }
                    );
                    this.merge_folder.notify["email-total"].connect(
                        () => { update_merge_folder_info_bar(); }
                    );

                    account_context.account.register_local_folder(
                        this.merge_folder
                    );
                    var main = this.client_application.get_active_main_window();
                    yield main.select_folder(this.merge_folder, true);
                }
            } catch (GLib.Error err) {
                debug("Displaying merge folder failed: %s", err.message);
            }
        }
    }

    private void update_merge_folder_info_bar() {
        // Translators: Info bar description for the mail merge
        // folder. The first string substitution the number of email
        // already sent, the second is the total number to send.
        this.merge_bar.description = ngettext(
            "Sent %u of %u",
            "Sent %u of %u",
            this.merge_folder.email_total
        ).printf(
            this.merge_folder.email_sent,
            this.merge_folder.email_total
        );
        this.merge_bar.primary_button = (
            (this.merge_folder.is_sending) ? this.pause_ui : this.start_ui
        );
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
        if (containing.any_match((f) => f.display_name in this.folder_names)) {
            try {
                var email = yield load_merge_email(target);
                if (global::MailMerge.Processor.is_mail_merge_template(email)) {
                    this.email.add_email_info_bar(
                        target.identifier,
                        new_template_email_info_bar(target.identifier),
                        INFO_BAR_PRIORITY
                    );
                }
            } catch (GLib.Error err) {
                warning("Error checking email for merge templates: %s",
                        err.message);
            }
        }
    }

    private async void update_composer(Composer composer) {
        if (true) {
            var load_action = new GLib.SimpleAction(ACTION_LOAD, null);
            load_action.activate.connect(
                () => { load_composer_data.begin(composer); }
            );
            composer.register_action(load_action);
            composer.append_menu_item(
                /// Translators: Menu item label for invoking mail
                /// merge in composer
                new Actionable(_("Mail Merge"), load_action)
            );
            composer.bind_property(
                "can-send",
                load_action,
                "enabled",
                BindingFlags.SYNC_CREATE |
                BindingFlags.INVERT_BOOLEAN);
        }
    }

    private async void load_composer_data(Composer composer) {
        var data = show_merge_data_chooser();
        if (data != null) {
            var insert_field_action = new GLib.SimpleAction(
                ACTION_INSERT_FIELD,
                GLib.VariantType.STRING
            );
            composer.register_action(insert_field_action);
            insert_field_action.activate.connect(
                (param) => {
                    insert_field(composer, (string) param);
                }
            );

            try {
                composer.set_action_bar(
                    yield new_composer_action_bar(
                        data,
                        composer.action_group_name
                    )
                );
            } catch (GLib.Error err) {
                debug("Error loading CSV: %s", err.message);
            }
        }

    }

    private InfoBar new_template_email_info_bar(EmailIdentifier target) {
        // Translators: Infobar status label for an email mail merge
        // template
        var bar = new InfoBar(_("Mail merge template"));
        bar.primary_button = new Actionable(
            // Translators: Info bar button label for performing a
            // mail-merge on an email template
            _("Merge"),
            this.merge_action,
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

    private async ActionBar new_composer_action_bar(GLib.File csv_file,
                                                    string action_group_name)
        throws GLib.Error {
        var info = yield csv_file.query_info_async(
            GLib.FileAttribute.STANDARD_DISPLAY_NAME,
            NONE,
            GLib.Priority.DEFAULT,
            this.cancellable
        );
        var input = yield csv_file.read_async(
            GLib.Priority.DEFAULT,
            this.cancellable
        );
        var csv = yield new global::MailMerge.Csv.Reader(
            input, this.cancellable
        );
        var record = yield csv.read_record();

        var text_fields_menu = new GLib.Menu();
        foreach (var field in record) {
            text_fields_menu.append(
                field,
                GLib.Action.print_detailed_name(
                    action_group_name + "." + ACTION_INSERT_FIELD,
                    field
                )
            );
        }

        var action_bar = new ActionBar();
        action_bar.append_item(
            /// Translators: Action bar menu button label for
            /// mail-merge plugin
            new ActionBar.MenuItem(_("Insert field"), text_fields_menu), START
        );
        action_bar.append_item(
            new ActionBar.LabelItem(info.get_display_name()), START
        );
        return action_bar;
    }

    private GLib.File? show_merge_data_chooser() {
        var chooser = new Gtk.FileChooserNative(
            /// Translators: File chooser title after invoking mail
            /// merge in composer
            _("Mail Merge"),
            null, OPEN,
            _("_Open"),
            _("_Cancel")
        );
        var csv_filter = new Gtk.FileFilter();
        /// Translators: File chooser filer label
        csv_filter.set_filter_name(_("Comma separated values (CSV)"));
        csv_filter.add_mime_type("text/csv");
        chooser.add_filter(csv_filter);

        return (
            chooser.run() == Gtk.ResponseType.ACCEPT
            ? chooser.get_file()
            : null
        );
    }

    private void insert_field(Composer composer, string field) {
        composer.insert_text(global::MailMerge.Processor.to_field(field));
    }

    private async Geary.Email load_merge_email(Email plugin) throws GLib.Error {
        Geary.Email? engine = this.client_plugins.to_engine_email(plugin);
        if (engine != null &&
            !engine.fields.fulfills(global::MailMerge.Processor.REQUIRED_FIELDS)) {
            var account_context = this.client_plugins.to_client_account(
                plugin.identifier.account
            );
            engine = yield account_context.emails.fetch_email_async(
                engine.id,
                global::MailMerge.Processor.REQUIRED_FIELDS,
                Geary.Folder.ListFlags.LOCAL_ONLY,
                this.cancellable
            );
        }
        if (engine == null) {
            throw new Geary.EngineError.NOT_FOUND("Plugin email not found");
        }
        return engine;
    }

    private void on_edit_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id =
                this.email_store.get_email_identifier_for_variant(target);
            if (id != null) {
                this.edit_email.begin(id);
            }
        }
    }

    private void on_merge_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id =
                this.email_store.get_email_identifier_for_variant(target);
            if (id != null) {
                this.merge_email.begin(id, null);
            }
        }
    }

    private void on_start_activated(GLib.Action action, GLib.Variant? target) {
        this.merge_folder.set_sending(true);
        update_merge_folder_info_bar();
    }

    private void on_pause_activated(GLib.Action action, GLib.Variant? target) {
        this.merge_folder.set_sending(false);
        update_merge_folder_info_bar();
    }

    private void on_composer_registered(Composer registered) {
        this.update_composer.begin(registered);
    }

    private void on_merge_closed() {
        if (this.merge_folder != null) {
            try {
                this.merge_folder.account.deregister_local_folder(
                    this.merge_folder
                );
            } catch (GLib.Error err) {
                warning("Error de-registering merge folder: %s", err.message);
            }
            this.merge_folder = null;
            this.merge_bar = null;
        }
    }

    private void on_folders_available(Gee.Collection<Folder> available) {
        foreach (var folder in available) {
            var engine_folder = this.client_plugins.to_engine_folder(folder);
            if (this.merge_folder == engine_folder) {
                try {
                    this.folders.register_folder_used_as(
                        folder,
                        // Translators: The name of the folder used to
                        // display merged email
                        _("Mail Merge"),
                        "mail-outbox-symbolic"
                    );
                } catch (GLib.Error err) {
                    warning(
                        "Failed to register %s as merge folder: %s",
                        folder.persistent_id,
                        err.message
                    );
                }
            }
        }
    }

    private void on_folder_selected(Folder selected) {
        var engine_folder = this.client_plugins.to_engine_folder(selected);
        if (this.merge_folder == engine_folder) {
            this.folders.add_folder_info_bar(
                selected, this.merge_bar, INFO_BAR_PRIORITY
            );
        }
    }

    private void on_email_displayed(Email email) {
        this.update_email.begin(email);
    }

}
