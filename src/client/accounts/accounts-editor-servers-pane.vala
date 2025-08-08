/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An account editor pane for editing server details for an account.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_servers_pane.ui")]
internal class Accounts.EditorServersPane : EditorPane, AccountPane, CommandPane {


    /** {@inheritDoc} */
    internal override weak Accounts.Editor editor { get; set; }

    /** {@inheritDoc} */
    internal Geary.AccountInformation account { get ; protected set; }

    /** {@inheritDoc} */
    internal Application.CommandStack commands {
        get; protected set; default = new Application.CommandStack();
    }

    /** {@inheritDoc} */
    internal override bool is_operation_running {
        get { return !this.sensitive; }
        protected set { update_operation_ui(value); }
    }

    /** {@inheritDoc} */
    internal override Cancellable? op_cancellable {
        get; protected set; default = new GLib.Cancellable();
    }

    private Geary.Engine engine;

    public Components.ValidatorGroup validators { get; construct set; }


    [GtkChild] private unowned Adw.ActionRow account_provider_row;
    [GtkChild] private unowned Adw.ActionRow service_provider_row;
    [GtkChild] private unowned Adw.SwitchRow save_drafts_row;
    [GtkChild] private unowned Adw.SwitchRow save_sent_row;

    [GtkChild] private unowned ServiceInformationWidget receiving_service_widget;
    [GtkChild] private unowned ServiceInformationWidget sending_service_widget;

    [GtkChild] private unowned Gtk.Button apply_button;
    [GtkChild] private unowned Gtk.Spinner apply_spinner;


    static construct {
        typeof(ServiceInformationWidget).ensure();

        install_action("apply", null, (Gtk.WidgetActionActivateFunc) action_apply);
    }


    public EditorServersPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;
        this.engine = editor.application.engine;


        // Details
        fill_in_account_provider(editor.accounts);
        fill_in_service_provider();

        this.receiving_service_widget.service = account.incoming;
        this.sending_service_widget.service = account.outgoing;

        bool services_editable = !(account.mediator is GoaMediator);
        this.receiving_service_widget.set_editable(services_editable);
        this.sending_service_widget.set_editable(services_editable);

        //XXX GTK4 Make sure we update save_drafts and save_sent

        // XXX GMail and Outlook auto-save sent mail so don't include save sent
        // option, but we shouldn't be hard-coding visible rows like this
        this.save_sent_row.visible = (account.service_provider == OTHER);

        // Misc plumbing

        connect_account_signals();
        connect_command_signals();
    }

    ~EditorServersPane() {
        disconnect_account_signals();
        disconnect_command_signals();
    }

    private void fill_in_account_provider(Manager accounts) {
        if (this.account.mediator is GoaMediator) {
            this.account_provider_row.subtitle = _("GNOME Online Accounts");

            var button = new Gtk.Button.from_icon_name("external-link-symbolic");
            button.valign = Gtk.Align.CENTER;
            button.clicked.connect((button) => {
                if (accounts.is_goa_account(this.account)) {
                    accounts.show_goa_account.begin(
                        account, this.op_cancellable,
                        (obj, res) => {
                            try {
                                accounts.show_goa_account.end(res);
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
            });
            this.account_provider_row.add_suffix(button);
        }
    }

    private void fill_in_service_provider() {
        switch (this.account.service_provider) {
        case Geary.ServiceProvider.GMAIL:
            this.service_provider_row.subtitle = _("Gmail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            this.service_provider_row.subtitle = _("Outlook.com");
            break;

        case Geary.ServiceProvider.OTHER:
            this.service_provider_row.subtitle = this.account.service_label;
            break;
        }
    }

    /** {@inheritDoc} */
    protected void command_executed() {
        this.editor.update_command_actions();
        this.apply_button.set_sensitive(this.commands.can_undo);
    }

    private async void save(GLib.Cancellable? cancellable) {
#if 0
        this.is_operation_running = true;

        // Only need to validate if a generic, local account since
        // other account types have read-only incoming/outgoing
        // settings
        bool is_valid = true;
        bool has_changed = false;
        if (this.account.service_provider == Geary.ServiceProvider.OTHER &&
            !this.editor.accounts.is_goa_account(this.account)) {
            is_valid = yield validate(cancellable);
            if (is_valid) {
                has_changed |= yield update_service(
                    this.account.incoming, this.incoming_mutable, cancellable
                );
                has_changed |= yield update_service(
                    this.account.outgoing, this.outgoing_mutable, cancellable
                );
            }
        }

        this.is_operation_running = false;

        if (is_valid) {
            if (this.save_drafts.value_changed) {
                has_changed = true;
            }

            if (this.save_sent.value_changed) {
                has_changed = true;
            }

            if (has_changed) {
                this.account.changed();
            }

            this.editor.pop_pane();
        } else {
            // Re-enable apply so that the same config can be re-tried
            // in the face of transient errors, without having to
            // change something to re-enable it
            this.apply_button.sensitive = true;

            // Undo these manually since it would have been updated
            // already by the command
            this.account.save_drafts = this.save_drafts.initial_value;
            this.account.save_sent = this.save_sent.initial_value;
        }
#endif
    }

    private async bool validate(GLib.Cancellable? cancellable) {
        // Use a copy here so we can handle any prompting needed
        // (auth, certs) directly, rather than through the main window
        Geary.AccountInformation local_account =
            new Geary.AccountInformation.copy(this.account);
        local_account.untrusted_host.connect(on_untrusted_host);

        string? message = null;
        bool imap_valid = false;

        try {
            yield this.engine.validate_imap(
                local_account,
                this.receiving_service_widget.service_mutable,
                cancellable
            );
            imap_valid = true;
        } catch (Geary.ImapError.UNAUTHENTICATED err) {
            debug("Error authenticating IMAP service: %s", err.message);
            // Translators: In-app notification label
            message = _("Check your receiving login and password");
        } catch (GLib.TlsError.BAD_CERTIFICATE err) {
            // Nothing to do here, since the untrusted host
            // handler will be dealing with it
            debug("Error validating IMAP certificate: %s", err.message);
        } catch (GLib.IOError.CANCELLED err) {
            // Nothing to do here, someone just cancelled
            debug("IMAP validation was cancelled: %s", err.message);
        } catch (GLib.Error err) {
            Geary.ErrorContext context = new Geary.ErrorContext(err);
            debug("Error validating IMAP service: %s",
                  context.format_full_error());
            // Translators: In-app notification label
            message = _("Check your receiving server details");
        }

        bool smtp_valid = false;
        if (imap_valid) {
            debug("Validating SMTP...");
            try {
                yield this.engine.validate_smtp(
                    local_account,
                    this.sending_service_widget.service_mutable,
                    this.receiving_service_widget.service_mutable.credentials,
                    cancellable
                );
                smtp_valid = true;
            } catch (Geary.SmtpError.AUTHENTICATION_FAILED err) {
                debug("Error authenticating SMTP service: %s", err.message);
                // There was an SMTP auth error, but IMAP already
                // succeeded, so the user probably needs to
                // specify custom creds here
                //XXX GTK4
                // this.outgoing_auth.value.source = Geary.Credentials.Requirement.CUSTOM;
                // Translators: In-app notification label
                message = _("Check your sending login and password");
            } catch (GLib.TlsError.BAD_CERTIFICATE err) {
                // Nothing to do here, since the untrusted host
                // handler will be dealing with it
                debug("Error validating SMTP certificate: %s", err.message);
            } catch (GLib.IOError.CANCELLED err) {
                // Nothing to do here, someone just cancelled
                debug("SMTP validation was cancelled: %s", err.message);
            } catch (GLib.Error err) {
                Geary.ErrorContext context = new Geary.ErrorContext(err);
                debug("Error validating SMTP service: %s",
                      context.format_full_error());
                // Translators: In-app notification label
                message = _("Check your sending server details");
            }
        }

        local_account.untrusted_host.disconnect(on_untrusted_host);

        bool is_valid = imap_valid && smtp_valid;
        debug("Validation complete, is valid: %s", is_valid.to_string());

        if (!is_valid && message != null) {
            this.editor.add_toast(
                new Adw.Toast(
                    // Translators: In-app notification label, the
                    // string substitution is a more detailed reason.
                    _("Account not updated: %s").printf(message)
                )
            );
        }

        return is_valid;
    }

    private async bool update_service(Geary.ServiceInformation existing,
                                      Geary.ServiceInformation copy,
                                      GLib.Cancellable cancellable) {
        return true;
#if 0
        bool has_changed = !existing.equal_to(copy);
        if (has_changed) {
            try {
                yield this.editor.accounts.update_local_credentials(
                    this.account, existing, copy, cancellable
                );
            } catch (GLib.Error err) {
                warning(
                    "Could not update %s %s credentials: %s",
                    this.account.id,
                    existing.protocol.to_value(),
                    err.message
                );
            }

            try {
                yield this.engine.update_account_service(
                    this.account, copy, cancellable
                );
            } catch (GLib.Error err) {
                warning(
                    "Could not update %s %s service: %s",
                    this.account.id,
                    existing.protocol.to_value(),
                    err.message
                );
            }
        }
        return has_changed;
#endif
    }

    private void update_operation_ui(bool is_running) {
        this.apply_spinner.visible = is_running;
        this.apply_button.sensitive = !is_running;
        this.sensitive = !is_running;
    }

    // [GtkCallback]
    // private void on_validators_changed(Components.ValidatorGroup validators,
    //                                    Components.Validator validator) {
    //     action_set_enabled("apply", validators.is_valid());
    // }

    // [GtkCallback]
    // private void on_validators_activated(Components.ValidatorGroup validators,
    //                                     Components.Validator validator) {
    //     if (validators.is_valid()) {
    //         activate_action("apply", null);
    //     }
    // }

    private void on_untrusted_host(Geary.AccountInformation account,
                                   Geary.ServiceInformation service,
                                   Geary.Endpoint endpoint,
                                   GLib.TlsConnection cx) {
        this.editor.prompt_pin_certificate.begin(
            account, service, endpoint, null,
            (obj, res) => {
                try {
                    this.editor.prompt_pin_certificate.end(res);
                } catch (Application.CertificateManagerError err) {
                    // All good, just drop back into the editor
                    // window.
                    return;
                }

                // Kick off another attempt to save
                this.save.begin(null);
            });
    }

    //XXX GTK4 we don't have a cancel button anymore
#if 0
    [GtkCallback]
    private void on_cancel_button_clicked() {
        if (this.is_operation_running) {
            cancel_operation();
        } else {
            this.editor.pop_pane();
        }
    }
#endif

    private void action_apply(string action_name, Variant? param) {
        this.save.begin(this.op_cancellable);
    }

}

private struct Accounts.InitialConfiguration {
    bool save_drafts;
    bool save_sent;
}


#if 0
private class zccounts.SaveDraftsRow : Adw.SwitchRow {

    public Geary.AccountInformation account { get; construct set; }

    public bool value_changed {
        get { return this.initial_value != this.value.state; }
    }
    public bool initial_value { get; construct set; }

    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public SaveDraftsRow(Geary.AccountInformation account,
                         Application.CommandStack commands,
                         GLib.Cancellable? cancellable) {
        Object(
            account: account,
            initial_value: account.save_drafts
        );

        this.commands = commands;
        this.cancellable = cancellable;
        this.account.notify["save-drafts"].connect(update);
        this.notify["active"].connect(on_activate);
        update();
    }

    private void update() {
        //XXX GTK4 I think we need to guard this with an if to not activate the
        // switch again
        this.active = this.account.save_drafts;
    }

    private void on_activate() {
        if (this.value.state != this.account.save_drafts) {
            this.commands.execute.begin(
                new Application.PropertyCommand<bool>(
                    this.account, "save_drafts", this.value.state
                ),
                this.cancellable
            );
        }
    }
}


private class Accounts.SaveSentRow :
    AccountRow<EditorServersPane,Gtk.Switch> {


    public bool value_changed {
        get { return this.initial_value != this.value.state; }
    }
    public bool initial_value { get; private set; }

    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public SaveSentRow(Geary.AccountInformation account,
                       Application.CommandStack commands,
                       GLib.Cancellable? cancellable) {
        Gtk.Switch value = new Gtk.Switch();
        base(
            account,
            // Translators: This label describes an account
            // preference.
            _("Save sent email on server"),
            value
        );
        update();
        this.commands = commands;
        this.cancellable = cancellable;
        this.activatable = false;
        this.initial_value = this.account.save_sent;
        this.account.notify["save-sent"].connect(on_account_changed);
        this.value.notify["active"].connect(on_activate);
    }

    public override void update() {
        this.value.state = this.account.save_sent;
    }

    private void on_activate() {
        if (this.value.state != this.account.save_sent) {
            this.commands.execute.begin(
                new Application.PropertyCommand<bool>(
                    this.account, "save_sent", this.value.state
                ),
                this.cancellable
            );
        }
    }

    private void on_account_changed() {
        update();
    }

}


private class Accounts.ServiceHostRow :
    ServiceRow<EditorServersPane,Gtk.Entry>, ValidatingRow<EditorServersPane> {


    public bool has_changed {
        get {
            return this.value.text.strip() != get_entry_text();
        }
    }

    private Components.EntryUndo value_undo;
    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public ServiceHostRow(Geary.AccountInformation account,
                          Geary.ServiceInformation service,
                          Application.CommandStack commands,
                          GLib.Cancellable? cancellable) {
        string label = "";
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

        base(account, service, label, new Gtk.Entry());
        this.commands = commands;
        this.cancellable = cancellable;
        this.activatable = false;
        this.validator = new Components.NetworkAddressValidator(this.value);

        // Update after the validator is wired up to ensure the value
        // is validated, wire up undo after updating so the default
        // value isn't undoable.
        setup_validator();
        update();
        this.value_undo = new Components.EntryUndo(this.value);
    }

    public override void update() {
        string value = get_entry_text();
        if (Geary.String.is_empty(value)) {
            value = _("None");
        }
        this.value.text = value;
    }

    protected void commit() {
        GLib.NetworkAddress? address =
            ((Components.NetworkAddressValidator) this.validator)
            .validated_address;
        if (address != null) {
            uint16 port = address.port != 0
            ? (uint16) address.port
            : this.service.get_default_port();
            this.commands.execute.begin(
                new Application.CommandSequence({
                        new Application.PropertyCommand<string>(
                            this.service, "host", address.hostname
                        ),
                        new Application.PropertyCommand<uint16>(
                            this.service, "port", port
                        )
                }),
                this.cancellable
            );
        }
    }

    private string? get_entry_text() {
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

}


private class Accounts.ServiceSecurityRow :
    ServiceRow<EditorServersPane,TlsComboBox> {


    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public ServiceSecurityRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service,
                              Application.CommandStack commands,
                              GLib.Cancellable? cancellable) {
        TlsComboBox value = new TlsComboBox();
        base(account, service, value.label, value);
        update();

        this.commands = commands;
        this.cancellable = cancellable;
        this.activatable = false;
        value.changed.connect(on_value_changed);
    }

    public override void update() {
        this.value.method = this.service.transport_security;
    }

    private void on_value_changed() {
        if (this.service.transport_security != this.value.method) {
            Application.Command cmd = new Application.PropertyCommand<uint>(
                this.service, "transport-security", this.value.method
            );

            debug("Security port: %u", this.service.port);

            // Update the port if we're currently using the default,
            // otherwise keep the custom port as-is.
            if (this.service.port == this.service.get_default_port()) {
                // Work out what the new port would be by copying the
                // service and applying the new security param up
                // front
                Geary.ServiceInformation copy =
                    new Geary.ServiceInformation.copy(this.service);
                copy.transport_security = this.value.method;
                cmd = new Application.CommandSequence(
                    {cmd,
                     new Application.PropertyCommand<uint>(
                         this.service, "port", copy.get_default_port()
                     )
                    });
            }
            this.commands.execute.begin(cmd, this.cancellable);
        }
    }

}


private class Accounts.ServiceLoginRow :
    ServiceRow<EditorServersPane,Gtk.Entry>, ValidatingRow<EditorServersPane> {

    public bool has_changed {
        get {
            return this.value.text.strip() != get_entry_text();
        }
    }

    private Components.EntryUndo value_undo;
    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;
    private ServicePasswordRow? password_row;


    public ServiceLoginRow(Geary.AccountInformation account,
                           Geary.ServiceInformation service,
                           Application.CommandStack commands,
                           GLib.Cancellable? cancellable,
                           ServicePasswordRow? password_row = null) {
        base(
            account,
            service,
            // Translators: Label for the user's login name for an
            // IMAP, SMTP, etc service
            _("Login name"),
            new Gtk.Entry()
        );

        this.commands = commands;
        this.cancellable = cancellable;
        this.activatable = false;
        this.validator = new Components.Validator(this.value);
        this.password_row = password_row;

        // If provided, only show the password row when the login has
        // changed
        if (password_row != null) {
            password_row.hide();
        }

        // Update after the validator is wired up to ensure the value
        // is validated, wire up undo after updating so the default
        // value isn't undoable.
        setup_validator();
        update();
        this.value_undo = new Components.EntryUndo(this.value);
    }

    public override void update() {
        this.value.text = get_entry_text();
    }

    protected void commit() {
        if (this.service.credentials != null) {
            Application.Command cmd =
                new Application.PropertyCommand<Geary.Credentials?>(
                    this.service,
                    "credentials",
                    new Geary.Credentials(
                        this.service.credentials.supported_method,
                        this.value.text
                    )
                );

            if (this.password_row != null) {
                cmd = new Application.CommandSequence({
                        cmd,
                        new Application.PropertyCommand<bool>(
                            this.password_row,
                            "visible",
                            true
                        )
                    });
            }

            this.commands.execute.begin(cmd, this.cancellable);
        }
    }

    private string? get_entry_text() {
        string? label = null;
        if (this.service.credentials != null) {
            string method = "%s";
            switch (this.service.credentials.supported_method) {
            case Geary.Credentials.Method.PASSWORD:
                this.value.remove_css_class("dim-label");
                break;

            case Geary.Credentials.Method.OAUTH2:
                // Add a suffix for OAuth2 auth so people know they
                // shouldn't expect to be prompted for a password

                // Translators: Label used when an account's IMAP or
                // SMTP service uses OAuth2. The string replacement is
                // the service's login name.
                method = _("%s using OAuth2");

                this.value.add_css_class("dim-label");
                break;
            }

            label = method.printf(this.service.credentials.user ?? "");
        } else if (this.service.protocol == Geary.Protocol.SMTP &&
                   this.service.credentials_requirement ==
                   Geary.Credentials.Requirement.USE_INCOMING) {
            label = _("Use receiving server login");
        } else {
            // Translators: Label used when no auth scheme is used
            // by an account's IMAP or SMTP service.
            label = _("None");
        }
        return label;
    }

}


private class Accounts.ServicePasswordRow :
    ServiceRow<EditorServersPane,Gtk.Entry>, ValidatingRow<EditorServersPane> {


    public bool has_changed {
        get {
            return this.value.text.strip() != get_entry_text();
        }
    }

    private Components.EntryUndo value_undo;
    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public ServicePasswordRow(Geary.AccountInformation account,
                              Geary.ServiceInformation service,
                              Application.CommandStack commands,
                              GLib.Cancellable? cancellable) {
        base(
            account,
            service,
            // Translators: Label for the user's password for an IMAP,
            // SMTP, etc service
            _("Password"),
            new Gtk.Entry()
        );

        this.commands = commands;
        this.cancellable = cancellable;
        this.activatable = false;
        this.value.visibility = false;
        this.value.input_purpose = Gtk.InputPurpose.PASSWORD;
        this.validator = new Components.Validator(this.value);

        // Update after the validator is wired up to ensure the value
        // is validated, wire up undo after updating so the default
        // value isn't undoable.
        setup_validator();
        update();
        this.value_undo = new Components.EntryUndo(this.value);
    }

    public override void update() {
        this.value.text = get_entry_text();
    }

    protected void commit() {
        if (this.service.credentials != null) {
            this.commands.execute.begin(
                new Application.PropertyCommand<Geary.Credentials?>(
                    this.service,
                    "credentials",
                    this.service.credentials.copy_with_token(this.value.text)
                ),
                this.cancellable
            );
        }
    }

    private string get_entry_text() {
        return (this.service.credentials != null)
            ? this.service.credentials.token ?? ""
            : "";
    }

}


private class Accounts.ServiceOutgoingAuthRow :
    ServiceRow<EditorServersPane,OutgoingAuthComboBox> {


    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;
    private Geary.ServiceInformation imap_service;


    public ServiceOutgoingAuthRow(Geary.AccountInformation account,
                                  Geary.ServiceInformation smtp_service,
                                  Geary.ServiceInformation imap_service,
                                  Application.CommandStack commands,
                                  GLib.Cancellable? cancellable) {
        OutgoingAuthComboBox value = new OutgoingAuthComboBox();
        base(account, smtp_service, value.label, value);
        update();

        this.commands = commands;
        this.cancellable = cancellable;
        this.imap_service = imap_service;
        this.activatable = false;
        value.changed.connect(on_value_changed);
    }

    public override void update() {
        this.value.source = this.service.credentials_requirement;
    }

    private void on_value_changed() {
        if (this.service.credentials_requirement != this.value.source) {
            // Need to update the credentials given the new
            // requirements, too
            Geary.Credentials? new_creds = null;
            if (this.value.source == CUSTOM) {
                new_creds = new Geary.Credentials(
                    Geary.Credentials.Method.PASSWORD, ""
                );
            }

            Application.Command[] commands = {
                new Application.PropertyCommand<Geary.Credentials?>(
                    this.service, "credentials", new_creds
                ),
                new Application.PropertyCommand<uint>(
                    this.service, "credentials-requirement", this.value.source
                )
            };

            // The default SMTP port also depends on the auth method
            // used, so also update the port here if we're currently
            // using the default, otherwise keep the custom port
            // as-is.
            if (this.service.port == this.service.get_default_port()) {
                // Work out what the new port would be by copying the
                // service and applying the new security param up
                // front
                Geary.ServiceInformation copy =
                    new Geary.ServiceInformation.copy(this.service);
                copy.credentials_requirement = this.value.source;
                commands += new Application.PropertyCommand<uint>(
                    this.service, "port", copy.get_default_port()
                );
            }

            this.commands.execute.begin(
                new Application.CommandSequence(commands), this.cancellable
            );
        }
    }

}
#endif
