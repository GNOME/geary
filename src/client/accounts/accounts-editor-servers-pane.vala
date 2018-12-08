/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An account editor pane for editing server details for an account.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_servers_pane.ui")]
internal class Accounts.EditorServersPane : Gtk.Grid, EditorPane, AccountPane {


    internal Geary.AccountInformation account { get ; protected set; }

    protected weak Accounts.Editor editor { get; set; }

    private Geary.Engine engine;

    // These are copies of the originals that can be updated before
    // validating on apply, without breaking anything.
    private Geary.ServiceInformation incoming_mutable;
    private Geary.ServiceInformation outgoing_mutable;


    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Overlay osd_overlay;

    [GtkChild]
    private Gtk.Grid pane_content;

    [GtkChild]
    private Gtk.Adjustment pane_adjustment;

    [GtkChild]
    private Gtk.ListBox details_list;

    [GtkChild]
    private Gtk.ListBox receiving_list;

    [GtkChild]
    private Gtk.ListBox sending_list;

    [GtkChild]
    private Gtk.Button apply_button;

    [GtkChild]
    private Gtk.Spinner apply_spinner;

    private SaveDraftsRow save_drafts;
    private ServiceSmtpAuthRow smtp_auth;
    private ServiceLoginRow smtp_login;


    public EditorServersPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;
        this.engine = ((GearyApplication) editor.application).engine;
        this.incoming_mutable = new Geary.ServiceInformation.copy(account.incoming);
        this.outgoing_mutable = new Geary.ServiceInformation.copy(account.outgoing);

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.details_list.set_header_func(Editor.seperator_headers);
        // Only add an account provider if it is esoteric enough.
        if (this.account.mediator is GoaMediator) {
            this.details_list.add(
                new AccountProviderRow(editor.accounts, this.account)
            );
        }
        ServiceProviderRow<EditorServersPane> service_provider =
            new ServiceProviderRow<EditorServersPane>(
                this.account.service_provider,
                this.account.service_label
            );
        service_provider.set_dim_label(true);
        service_provider.activatable = false;
        this.details_list.add(service_provider);
        this.save_drafts = new SaveDraftsRow(this.account);
        this.details_list.add(this.save_drafts);

        this.receiving_list.set_header_func(Editor.seperator_headers);
        this.receiving_list.add(new ServiceHostRow(account, this.incoming_mutable));
        this.receiving_list.add(new ServiceSecurityRow(account, this.incoming_mutable));
        this.receiving_list.add(new ServiceLoginRow(account, this.incoming_mutable));

        this.sending_list.set_header_func(Editor.seperator_headers);
        this.sending_list.add(new ServiceHostRow(account, this.outgoing_mutable));
        this.sending_list.add(new ServiceSecurityRow(account, this.outgoing_mutable));
        this.smtp_auth = new ServiceSmtpAuthRow(
            account, this.outgoing_mutable, this.incoming_mutable
        );
        this.smtp_auth.value.changed.connect(on_smtp_auth_changed);
        this.sending_list.add(this.smtp_auth);
        this.smtp_login = new ServiceLoginRow(account, this.outgoing_mutable);
        this.sending_list.add(this.smtp_login);

        this.account.changed.connect(on_account_changed);

        update_header();
        update_smtp_auth();
    }

    ~EditorServersPane() {
        this.account.changed.disconnect(on_account_changed);
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private async void save(GLib.Cancellable? cancellable) {
        this.apply_button.set_sensitive(false);
        this.apply_spinner.show();
        this.apply_spinner.start();

        // Only need to validate if a generic account
        bool is_valid = true;
        bool has_changed = false;
        if (this.account.service_provider == Geary.ServiceProvider.OTHER) {
            is_valid = yield validate(cancellable);

            if (is_valid) {
                try {
                    has_changed = this.engine.update_account_service(
                        this.account, incoming_mutable
                    );
                    has_changed = this.engine.update_account_service(
                        this.account, outgoing_mutable
                    );
                } catch (Geary.EngineError err) {
                    warning("Could not update account services: %s", err.message);
                }
            }
        }

        if (is_valid) {
            if (this.save_drafts.value_changed) {
                this.account.save_drafts = this.save_drafts.value.state;
                has_changed = true;
            }

            if (has_changed) {
                this.account.changed();
            }

            this.editor.pop();
        }

        this.apply_button.set_sensitive(true);
        this.apply_spinner.stop();
        this.apply_spinner.hide();
    }

    private async bool validate(GLib.Cancellable? cancellable) {
        string message = "";
        bool imap_valid = false;
        try {
            yield this.engine.validate_imap(
                this.account, this.incoming_mutable, cancellable
            );
            imap_valid = true;
        } catch (Geary.ImapError.UNAUTHENTICATED err) {
            debug("Error authenticating IMAP service: %s", err.message);
            // Translators: In-app notification label
            message = _("Check your receiving login and password");
        } catch (GLib.Error err) {
            debug("Error validating IMAP service: %s", err.message);
            // Translators: In-app notification label
            message = _("Check your receiving server details");
        }

        bool smtp_valid = false;
        if (imap_valid) {
            debug("Validating SMTP...");
            try {
                yield this.engine.validate_smtp(
                    this.account,
                    this.outgoing_mutable,
                    this.incoming_mutable.credentials,
                    cancellable
                );
                smtp_valid = true;
            } catch (Geary.SmtpError.AUTHENTICATION_FAILED err) {
                debug("Error authenticating SMTP service: %s", err.message);
                // There was an SMTP auth error, but IMAP already
                // succeeded, so the user probably needs to
                // specify custom creds here
                this.smtp_auth.value.source = Geary.Credentials.Requirement.CUSTOM;
                // Translators: In-app notification label
                message = _("Check your sending login and password");
            } catch (GLib.Error err) {
                debug("Error validating SMTP service: %s", err.message);
                    // Translators: In-app notification label
                    message = _("Check your sending server details");
            }
        }

        bool is_valid = imap_valid && smtp_valid;
        debug("Validation complete, is valid: %s", is_valid.to_string());

        if (!is_valid) {
            add_notification(
                new InAppNotification(
                    // Translators: In-app notification label, the
                    // string substitution is a more detailed reason.
                    _("Account not updated: %s").printf(message)
                )
            );
        }

        return is_valid;
    }

    private void add_notification(InAppNotification notification) {
        this.osd_overlay.add_overlay(notification);
        notification.show();
    }

    private void update_smtp_auth() {
        this.smtp_login.set_visible(
            this.smtp_auth.value.source == Geary.Credentials.Requirement.CUSTOM
        );
    }

    [GtkCallback]
    private void on_cancel_button_clicked() {
        this.editor.pop();
    }

    [GtkCallback]
    private void on_apply_button_clicked() {
        this.save.begin(null);
    }

    [GtkCallback]
    private bool on_list_keynav_failed(Gtk.Widget widget,
                                       Gtk.DirectionType direction) {
        bool ret = Gdk.EVENT_PROPAGATE;
        Gtk.Container? next = null;
        if (direction == Gtk.DirectionType.DOWN) {
            if (widget == this.details_list) {
                next = this.receiving_list;
            } else if (widget == this.receiving_list) {
                next = this.sending_list;
            }
        } else if (direction == Gtk.DirectionType.UP) {
            if (widget == this.sending_list) {
                next = this.receiving_list;
            } else if (widget == this.receiving_list) {
                next = this.details_list;
            }
        }

        if (next != null) {
            next.child_focus(direction);
            ret = Gdk.EVENT_STOP;
        }
        return ret;
    }

    private void on_account_changed() {
        update_header();
    }

    private void on_smtp_auth_changed() {
        update_smtp_auth();
    }

    [GtkCallback]
    private void on_activate(Gtk.ListBoxRow row) {
        Accounts.EditorRow<EditorServersPane> server_row =
            row as Accounts.EditorRow<EditorServersPane>;
        if (server_row != null) {
            server_row.activated(this);
        }
    }

}


private class Accounts.AccountProviderRow :
    AccountRow<EditorServersPane,Gtk.Label> {

    private Manager accounts;

    public AccountProviderRow(Manager accounts,
                              Geary.AccountInformation account) {
        base(
            account,
            // Translators: This label describes the program that
            // created the account, e.g. an SSO service like GOA, or
            // locally by Geary.
            _("Account source"),
            new Gtk.Label("")
        );

        this.accounts = accounts;
        update();
    }

    public override void update() {
        string? source = null;
        bool enabled = false;
        if (this.account.mediator is GoaMediator) {
            source = _("GNOME Online Accounts");
            enabled = true;
        } else {
            source = _("Geary");
        }

        this.value.set_text(source);
        this.set_activatable(enabled);
        Gtk.StyleContext style = this.value.get_style_context();
        if (enabled) {
            style.remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
        } else {
            style.add_class(Gtk.STYLE_CLASS_DIM_LABEL);
        }
    }

    public override void activated(EditorServersPane pane) {
        if (this.accounts.is_goa_account(this.account)) {
            this.accounts.show_goa_account.begin(
                account, null,
                (obj, res) => {
                    try {
                        this.accounts.show_goa_account.end(res);
                    } catch (GLib.Error err) {
                        // XXX display an error to the user
                        debug(
                            "Failed to show GOA account \"%s\": %s",
                            account.id,
                            err.message
                        );
                    }
                });
        }
    }

}


private class Accounts.SaveDraftsRow :
    AccountRow<EditorServersPane,Gtk.Switch> {


    public bool value_changed {
        get { return this.initial_value != this.value.state; }
    }

    private bool initial_value;


    public SaveDraftsRow(Geary.AccountInformation account) {
        Gtk.Switch value = new Gtk.Switch();
        base(
            account,
            // Translators: This label describes an account
            // preference.
            _("Save drafts on server"),
            value
        );
        set_activatable(false);
        update();
        value.notify["active"].connect(on_activate);
    }

    public override void update() {
        this.initial_value = this.account.save_drafts;
        this.value.state = this.initial_value;
    }

    private void on_activate() {
        this.account.save_drafts = this.value.state;
    }

}


private class Accounts.ServiceHostRow :
    ServiceRow<EditorServersPane,Gtk.Label> {

    public ServiceHostRow(Geary.AccountInformation account,
                          Geary.ServiceInformation service) {
        string label = _("Unknown");
        switch (service.protocol) {
        case Geary.Protocol.IMAP:
            // Translators: This label describes the host name or IP
            // address and port used by an account's IMAP service.
            label = _("IMAP server");
            break;

        case Geary.Protocol.SMTP:
            // Translators: This label describes the host name or IP
            // address and port used by an account's SMTP service.
            label = _("SMTP server");
            break;
        }

        base(
            account,
            service,
            label,
            new Gtk.Label("")
        );

        update();
    }

    public override void activated(EditorServersPane pane) {
        string? text = get_host_text() ?? "";
        Gtk.Entry entry = new Gtk.Entry();
        entry.set_text(text);
        entry.set_placeholder_text(text);
        entry.set_width_chars(20);
        entry.show();

        EditorPopover popover = new EditorPopover();
        popover.set_relative_to(this.value);
        popover.layout.add(entry);
        popover.add_validator(new Components.NetworkAddressValidator(entry));
        popover.valid_activated.connect(on_popover_activate);
        popover.popup();
    }

    public override void update() {
        string value = get_host_text();
        if (Geary.String.is_empty(value)) {
            value = _("None");
        }
        this.value.set_text(value);
    }

    private string? get_host_text() {
        string? value = this.service.host ?? "";
        if (!Geary.String.is_empty(value)) {
            // Only show the port if it not the appropriate default port
            uint16 port = this.service.port;
            if (port != this.service.get_default_port()) {
                value = "%s:%d".printf(value, this.service.port);
            }
        }
        return value;
    }

    private void on_popover_activate(EditorPopover popover) {
        Components.NetworkAddressValidator validator =
            (Components.NetworkAddressValidator) Geary.traverse(
                popover.validators
            ).first();

        GLib.NetworkAddress? address = validator.validated_address;
        if (address != null) {
            this.service.host = address.hostname;
            this.service.port = address.port != 0
                ? (uint16) address.port
                : this.service.get_default_port();
        }

        popover.popdown();
    }

}


private class Accounts.ServiceSecurityRow :
    ServiceRow<EditorServersPane,TlsComboBox> {

    public ServiceSecurityRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service) {
        TlsComboBox value = new TlsComboBox();
        base(account, service, value.label, value);
        set_activatable(false);
        value.changed.connect(on_value_changed);
        update();
    }

    public override void update() {
        this.value.method = this.service.transport_security;
    }

    private void on_value_changed() {
        if (this.service.transport_security != this.value.method) {
            // Update the port if we're currently using the default,
            // otherwise keep the custom port as-is.
            bool update_port = (
                this.service.port == this.service.get_default_port()
            );
            this.service.transport_security = this.value.method;
            if (update_port) {
                this.service.port = this.service.get_default_port();
            }
        }
    }

}


private class Accounts.ServiceLoginRow :
    ServiceRow<EditorServersPane,Gtk.Label> {

    public ServiceLoginRow(Geary.AccountInformation account,
                           Geary.ServiceInformation service) {
        base(
            account,
            service,
            // Translators: This label describes the authentication
            // scheme used by an account's IMAP or SMTP service.
            _("Login name"),
            new Gtk.Label("")
        );

        this.value.ellipsize = Pango.EllipsizeMode.MIDDLE;
        update();
    }

    public override void activated(EditorServersPane pane) {
        string? value = null;
        if (this.service.credentials != null) {
            value = this.service.credentials.user;
        }
        Gtk.Entry entry = new Gtk.Entry();
        entry.set_text(value ?? "");
        entry.set_placeholder_text(value ?? "");
        entry.set_width_chars(20);
        entry.show();

        EditorPopover popover = new EditorPopover();
        popover.set_relative_to(this.value);
        popover.layout.add(entry);
        popover.add_validator(new Components.Validator(entry));
        popover.valid_activated.connect(on_popover_activate);
        popover.popup();
    }

    public override void update() {
        this.value.set_text(get_login_text());
    }

    private string? get_login_text() {
        string? label = null;
        if (this.service.credentials != null) {
            string method = "%s";
            Gtk.StyleContext value_style = this.value.get_style_context();
            switch (this.service.credentials.supported_method) {
            case Geary.Credentials.Method.PASSWORD:
                this.activatable = true;
                value_style.remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
                break;

            case Geary.Credentials.Method.OAUTH2:
                // Add a suffix for OAuth2 auth so people know they
                // shouldn't expect to be prompted for a password

                // Translators: Label used when an account's IMAP or
                // SMTP service uses OAuth2. The string replacement is
                // the service's login name.
                method = _("%s using OAuth2");

                this.activatable = false;
                value_style.add_class(Gtk.STYLE_CLASS_DIM_LABEL);
                break;
            }

            string? login = this.service.credentials.user;
            if (Geary.String.is_empty(login)) {
                login = _("Unknown");
            }

            label = method.printf(login);
        } else if (this.service.protocol == Geary.Protocol.SMTP &&
                   this.service.credentials_requirement ==
                   Geary.Credentials.Requirement.USE_INCOMING) {
            label = _("Use incoming server login");
        } else {
            // Translators: Label used when no auth scheme is used
            // by an account's IMAP or SMTP service.
            label = _("None");
        }
        return label;
    }

    private void on_popover_activate(EditorPopover popover) {
        Components.Validator validator =
            Geary.traverse(popover.validators).first();
       this.service.credentials =
           this.service.credentials.copy_with_user(validator.target.text);
        popover.popdown();
    }

}

private class Accounts.ServiceSmtpAuthRow :
    ServiceRow<EditorServersPane,SmtpAuthComboBox> {


    Geary.ServiceInformation imap_service;


    public ServiceSmtpAuthRow(Geary.AccountInformation account,
                              Geary.ServiceInformation smtp_service,
                              Geary.ServiceInformation imap_service) {
        SmtpAuthComboBox value = new SmtpAuthComboBox();
        base(account, smtp_service, value.label, value);
        this.imap_service = imap_service;
        this.activatable = false;
        value.changed.connect(on_value_changed);
        update();
    }

    public override void update() {
        this.value.source = this.service.credentials_requirement;
    }

    private void on_value_changed() {
        if (this.service.credentials_requirement != this.value.source) {
            // The default SMTP port also depends on the auth method
            // used, so also update the port here if we're currently
            // using the default, otherwise keep the custom port
            // as-is.
            bool update_port = (
                this.service.port == this.service.get_default_port()
            );
            this.service.credentials_requirement = this.value.source;
            this.service.credentials =
                (this.service.credentials_requirement != CUSTOM)
                ? null
                : new Geary.Credentials(Geary.Credentials.Method.PASSWORD, "");
            if (update_port) {
                this.service.port = this.service.get_default_port();
            }
        }
    }

}
