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
 * Plugin to Fill in and send email templates using a spreadsheet.
 */
public class Plugin.MailMerge :
    PluginBase, FolderExtension, EmailExtension {


    private const string FIELD_START = "{{";
    private const string FIELD_END = "}}";


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
    private const string ACTION_MERGE = "merge-template";

    private const int INFO_BAR_PRIORITY = 10;


    public FolderContext folders {
        get; set construct;
    }

    public EmailContext email {
        get; set construct;
    }


    private FolderStore? folder_store = null;
    private EmailStore? email_store = null;

    private GLib.SimpleAction? edit_action = null;
    private GLib.SimpleAction? merge_action = null;

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

    private async bool is_mail_merge_template(Email email) {
        var found = (
            (email.subject != null &&
             contains_field(email.subject.to_rfc822_string())) ||
            (email.to != null &&
             contains_field(email.to.to_rfc822_string())) ||
            (email.cc != null &&
             contains_field(email.cc.to_rfc822_string())) ||
            (email.bcc != null &&
             contains_field(email.bcc.to_rfc822_string())) ||
            (email.reply_to != null &&
             contains_field(email.bcc.to_rfc822_string())) ||
            (email.sender != null &&
             contains_field(email.sender.to_rfc822_string()))
        );
        if (!found) {
            string body = "";
            try {
                body = yield email.load_body_as(PLAIN, true, this.cancellable);
            } catch (GLib.Error err) {
                debug("Failed to load template body: %s", err.message);
            }
            found = contains_field(body);
        }
        return found;
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

    private async void merge_email(EmailIdentifier id) {

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
        if (containing.any_match((f) => f.display_name in this.folder_names) &&
            yield is_mail_merge_template(target)) {
            this.email.add_email_info_bar(
                target.identifier,
                new_template_email_info_bar(target.identifier),
                INFO_BAR_PRIORITY
            );
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

    private bool contains_field(string value) {
        var found = false;
        var index = 0;
        while (!found) {
            var field_start = value.index_of(FIELD_START, index);
            if (field_start < 0) {
                break;
            }
            found = parse_field((string) value.data[field_start:-1]) != null;
            index = field_start + 1;
        }
        return found;
    }

    private string? parse_field(string value) {
        string? field = null;
        if (value.has_prefix(FIELD_START)) {
            int start = FIELD_START.length;
            int end = value.index_of(FIELD_END, start);
            if (end >= 0) {
                field = value.substring(start, end - FIELD_END.length).strip();
            }
        }
        return field;
    }

    private void on_edit_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id =
                this.email_store.get_email_identifier_from_variant(target);
            if (id != null) {
                this.edit_email.begin(id);
            }
        }
    }

    private void on_merge_activated(GLib.Action action, GLib.Variant? target) {
        if (this.email_store != null && target != null) {
            EmailIdentifier? id =
                this.email_store.get_email_identifier_from_variant(target);
            if (id != null) {
                this.merge_email.begin(id);
            }
        }
    }

    private void on_email_displayed(Email email) {
        this.update_email.begin(email);
    }

}
