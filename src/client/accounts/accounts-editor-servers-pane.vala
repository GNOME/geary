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
internal class Accounts.EditorServersPane :
    Gtk.Grid, EditorPane, AccountPane, CommandPane {


    /** {@inheritDoc} */
    internal weak Accounts.Editor editor { get; set; }

    /** {@inheritDoc} */
    internal Geary.AccountInformation account { get ; protected set; }

    /** {@inheritDoc} */
    internal Application.CommandStack commands {
        get; protected set; default = new Application.CommandStack();
    }

    /** {@inheritDoc} */
    internal Gtk.Widget initial_widget {
        get { return this.details_list; }
    }

    /** {@inheritDoc} */
    internal bool is_operation_running {
        get { return !this.sensitive; }
        protected set { update_operation_ui(value); }
    }

    /** {@inheritDoc} */
    internal GLib.Cancellable? op_cancellable {
        get; protected set; default = new GLib.Cancellable();
    }

    private Geary.Engine engine;

    // These are copies of the originals that can be updated before
    // validating on apply, without breaking anything.
    private Geary.ServiceInformation incoming_mutable;
    private Geary.ServiceInformation outgoing_mutable;

    private Gee.List<Components.Validator> validators =
        new Gee.LinkedList<Components.Validator>();


    [GtkChild] private unowned Gtk.HeaderBar header;

    [GtkChild] private unowned Gtk.Grid pane_content;

    [GtkChild] private unowned Gtk.Adjustment pane_adjustment;

    [GtkChild] private unowned Gtk.ListBox details_list;

    [GtkChild] private unowned Gtk.ListBox receiving_list;

    [GtkChild] private unowned Gtk.ListBox sending_list;

    [GtkChild] private unowned Gtk.Button apply_button;

    [GtkChild] private unowned Gtk.Spinner apply_spinner;

    private SaveDraftsRow save_drafts;
    private SaveSentRow save_sent;

    private ServiceLoginRow incoming_login;
    private ServicePasswordRow incoming_password;

    private ServiceOutgoingAuthRow outgoing_auth;
    private ServiceLoginRow outgoing_login;
    private ServicePasswordRow outgoing_password;


    public EditorServersPane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;
        this.engine = editor.application.engine;
        this.incoming_mutable = new Geary.ServiceInformation.copy(account.incoming);
        this.outgoing_mutable = new Geary.ServiceInformation.copy(account.outgoing);

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        // Details

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
        add_row(this.details_list, service_provider);

        this.save_drafts = new SaveDraftsRow(
            this.account, this.commands, this.op_cancellable
        );
        add_row(this.details_list, this.save_drafts);

        this.save_sent = new SaveSentRow(
            this.account, this.commands, this.op_cancellable
        );
        switch (account.service_provider) {
        case OTHER:
            add_row(this.details_list, this.save_sent);
            break;
        default:
            // XXX GMail and Outlook auto-save sent mail so don't
            // include save sent option, but we shouldn't be
            // hard-coding visible rows like this
            break;
        }

        // Receiving

        this.receiving_list.set_header_func(Editor.seperator_headers);
        add_row(
            this.receiving_list,
            new ServiceHostRow(
                account,
                this.incoming_mutable,
                this.commands,
                this.op_cancellable
            )
        );
        add_row(
            this.receiving_list,
            new ServiceSecurityRow(
                account,
                this.incoming_mutable,
                this.commands,
                this.op_cancellable
            )
        );

        this.incoming_password = new ServicePasswordRow(
            account,
            this.incoming_mutable,
            this.commands,
            this.op_cancellable
        );

        this.incoming_login = new ServiceLoginRow(
            account,
            this.incoming_mutable,
            this.commands,
            this.op_cancellable,
            this.incoming_password
        );

        add_row(this.receiving_list, this.incoming_login);
        add_row(this.receiving_list, this.incoming_password);

        // Sending

        this.sending_list.set_header_func(Editor.seperator_headers);
        add_row(
            this.sending_list,
            new ServiceHostRow(
                account,
                this.outgoing_mutable,
                this.commands,
                this.op_cancellable
            )
        );
        add_row(
            this.sending_list,
            new ServiceSecurityRow(
                account,
                this.outgoing_mutable,
                this.commands,
                this.op_cancellable
            )
        );
        this.outgoing_auth = new ServiceOutgoingAuthRow(
            account,
            this.outgoing_mutable,
            this.incoming_mutable,
            this.commands,
            this.op_cancellable
        );
        this.outgoing_auth.value.changed.connect(on_outgoing_auth_changed);
        add_row(this.sending_list, this.outgoing_auth);

        this.outgoing_password = new ServicePasswordRow(
            account,
            this.outgoing_mutable,
            this.commands,
            this.op_cancellable
        );

        this.outgoing_login = new ServiceLoginRow(
            account,
            this.outgoing_mutable,
            this.commands,
            this.op_cancellable,
            this.outgoing_password
        );

        add_row(this.sending_list, this.outgoing_login);
        add_row(this.sending_list, this.outgoing_password);

        // Misc plumbing

        connect_account_signals();
        connect_command_signals();

        update_outgoing_auth();
    }

    ~EditorServersPane() {
        disconnect_account_signals();
        disconnect_command_signals();
    }

    /** {@inheritDoc} */
    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    /** {@inheritDoc} */
    protected void command_executed() {
        this.editor.update_command_actions();
        this.apply_button.set_sensitive(this.commands.can_undo);
    }

    private bool is_valid() {
        return Geary.traverse(this.validators).all((v) => v.is_valid);
    }

    private async void save(GLib.Cancellable? cancellable) {
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

            this.editor.pop();
        } else {
            // Re-enable apply so that the same config can be re-tried
            // in the face of transient errors, without having to
            // change something to re-enable it
            this.apply_button.set_sensitive(true);

            // Undo these manually since it would have been updated
            // already by the command
            this.account.save_drafts = this.save_drafts.initial_value;
            this.account.save_sent = this.save_sent.initial_value;
        }
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
                local_account, this.incoming_mutable, cancellable
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
                this.outgoing_auth.value.source = Geary.Credentials.Requirement.CUSTOM;
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
            this.editor.add_notification(
                new Components.InAppNotification(
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
    }

    private void add_row(Gtk.ListBox list, EditorRow<EditorServersPane> row) {
        list.add(row);
        ValidatingRow? validating = row as ValidatingRow;
        if (validating != null) {
            validating.changed.connect(on_validator_changed);
            validating.validator.activated.connect_after(on_validator_activated);
            this.validators.add(validating.validator);
        }
    }

    private void update_outgoing_auth() {
        this.outgoing_login.set_visible(
            this.outgoing_auth.value.source == CUSTOM
        );
    }

    private void update_operation_ui(bool is_running) {
        this.apply_spinner.visible = is_running;
        this.apply_spinner.active = is_running;
        this.apply_button.sensitive = !is_running;
        this.sensitive = !is_running;
    }

    private void on_validator_changed() {
        this.apply_button.set_sensitive(is_valid());
    }

    private void on_validator_activated() {
        if (is_valid()) {
            this.apply_button.clicked();
        }
    }

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

    [GtkCallback]
    private void on_cancel_button_clicked() {
        if (this.is_operation_running) {
            cancel_operation();
        } else {
            this.editor.pop();
        }
    }

    [GtkCallback]
    private void on_apply_button_clicked() {
        this.save.begin(this.op_cancellable);
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

    private void on_outgoing_auth_changed() {
        update_outgoing_auth();
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
                account, pane.op_cancellable,
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
    public bool initial_value { get; private set; }

    private Application.CommandStack commands;
    private GLib.Cancellable? cancellable;


    public SaveDraftsRow(Geary.AccountInformation account,
                         Application.CommandStack commands,
                         GLib.Cancellable? cancellable) {
        Gtk.Switch value = new Gtk.Switch();
        base(
            account,
            // Translators: This label describes an account
            // preference.
            _("Save draft email on server"),
            value
        );
        update();
        this.commands = commands;
        this.cancellable = cancellable;
        this.activatable = false;
        this.initial_value = this.account.save_drafts;
        this.account.notify["save-drafts"].connect(on_account_changed);
        this.value.notify["active"].connect(on_activate);
    }

    public override void update() {
        this.value.state = this.account.save_drafts;
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

    private void on_account_changed() {
        update();
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


    public Components.Validator validator {
        get; protected set;
    }

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


    public Components.Validator validator {
        get; protected set;
    }

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
            Gtk.StyleContext value_style = this.value.get_style_context();
            switch (this.service.credentials.supported_method) {
            case Geary.Credentials.Method.PASSWORD:
                value_style.remove_class(Gtk.STYLE_CLASS_DIM_LABEL);
                break;

            case Geary.Credentials.Method.OAUTH2:
                // Add a suffix for OAuth2 auth so people know they
                // shouldn't expect to be prompted for a password

                // Translators: Label used when an account's IMAP or
                // SMTP service uses OAuth2. The string replacement is
                // the service's login name.
                method = _("%s using OAuth2");

                value_style.add_class(Gtk.STYLE_CLASS_DIM_LABEL);
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


    public Components.Validator validator {
        get; protected set;
    }

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
