/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for adding a new account.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_add_pane.ui")]
internal class Accounts.EditorAddPane : Gtk.Grid, EditorPane {


    internal Gtk.Widget initial_widget {
        get { return this.real_name.value; }
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

    protected weak Accounts.Editor editor { get; set; }

    private Geary.ServiceProvider provider;

    private Manager accounts;
    private Geary.Engine engine;


    [GtkChild] private unowned Gtk.HeaderBar header;

    [GtkChild] private unowned Gtk.Stack stack;

    [GtkChild] private unowned Gtk.Adjustment pane_adjustment;

    [GtkChild] private unowned Gtk.ListBox details_list;

    [GtkChild] private unowned Gtk.ListBox receiving_list;

    [GtkChild] private unowned Gtk.ListBox sending_list;

    [GtkChild] private unowned Gtk.Button action_button;

    [GtkChild] private unowned Gtk.Button back_button;

    [GtkChild] private unowned Gtk.Spinner action_spinner;

    private NameRow real_name;
    private EmailRow email = new EmailRow();
    private string last_valid_email = "";
    private string last_valid_hostname = "";

    private GLib.Cancellable auto_config_cancellable = new GLib.Cancellable();

    private HostnameRow imap_hostname = new HostnameRow(Geary.Protocol.IMAP);
    private TransportSecurityRow imap_tls = new TransportSecurityRow();
    private LoginRow imap_login = new LoginRow();
    private PasswordRow imap_password = new PasswordRow();

    private HostnameRow smtp_hostname = new HostnameRow(Geary.Protocol.SMTP);
    private TransportSecurityRow smtp_tls = new TransportSecurityRow();
    private OutgoingAuthRow smtp_auth = new OutgoingAuthRow();
    private LoginRow smtp_login = new LoginRow();
    private PasswordRow smtp_password = new PasswordRow();

    private bool controls_valid = false;


    internal EditorAddPane(Editor editor) {
        this.editor = editor;
        this.provider = Geary.ServiceProvider.OTHER;

        this.accounts = editor.application.controller.account_manager;
        this.engine = editor.application.engine;

        this.stack.set_focus_vadjustment(this.pane_adjustment);

        this.details_list.set_header_func(Editor.seperator_headers);
        this.receiving_list.set_header_func(Editor.seperator_headers);
        this.sending_list.set_header_func(Editor.seperator_headers);

        this.real_name = new NameRow(this.accounts.get_account_name());

        this.details_list.add(this.real_name);
        this.details_list.add(this.email);

        this.real_name.validator.state_changed.connect(on_validated);
        this.real_name.value.activate.connect(on_activated);
        this.email.validator.state_changed.connect(on_validated);
        this.email.value.activate.connect(on_activated);
        this.email.value.changed.connect(on_email_changed);

        this.imap_hostname.validator.state_changed.connect(on_validated);
        this.imap_hostname.value.activate.connect(on_activated);
        this.imap_tls.hide();
        this.imap_login.validator.state_changed.connect(on_validated);
        this.imap_login.value.activate.connect(on_activated);
        this.imap_password.validator.state_changed.connect(on_validated);
        this.imap_password.value.activate.connect(on_activated);

        this.smtp_hostname.validator.state_changed.connect(on_validated);
        this.smtp_hostname.value.activate.connect(on_activated);
        this.smtp_tls.hide();
        this.smtp_auth.value.changed.connect(on_smtp_auth_changed);
        this.smtp_login.validator.state_changed.connect(on_validated);
        this.smtp_login.value.activate.connect(on_activated);
        this.smtp_password.validator.state_changed.connect(on_validated);
        this.smtp_password.value.activate.connect(on_activated);

        this.receiving_list.add(this.imap_hostname);
        this.receiving_list.add(this.imap_tls);
        this.receiving_list.add(this.imap_login);
        this.receiving_list.add(this.imap_password);

        this.sending_list.add(this.smtp_hostname);
        this.sending_list.add(this.smtp_tls);
        this.sending_list.add(this.smtp_auth);
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private async void validate_account(GLib.Cancellable? cancellable) {
        this.is_operation_running = true;

        bool is_valid = false;
        string? message = null;
        Gtk.Widget? to_focus = null;

        Geary.AccountInformation account =
            yield this.accounts.new_orphan_account(
                this.provider,
                new Geary.RFC822.MailboxAddress(
                    this.real_name.value.text.strip(),
                    this.email.value.text.strip()
                ),
                cancellable
            );

        account.incoming = new_imap_service();
        account.outgoing = new_smtp_service();
        account.untrusted_host.connect(on_untrusted_host);

        if (this.provider == Geary.ServiceProvider.OTHER &&
                this.imap_hostname.get_visible()) {
            bool imap_valid = false;
            bool smtp_valid = false;

            try {
                yield this.engine.validate_imap(
                    account, account.incoming, cancellable
                );
                imap_valid = true;
            } catch (Geary.ImapError.UNAUTHENTICATED err) {
                debug("Error authenticating IMAP service: %s", err.message);
                to_focus = this.imap_login.value;
                // Translators: In-app notification label
                message = _("Check your receiving login and password");
            } catch (GLib.TlsError.BAD_CERTIFICATE err) {
                debug("Error validating IMAP certificate: %s", err.message);
                // Nothing to do here, since the untrusted host
                // handler will be dealing with it
            } catch (GLib.IOError.CANCELLED err) {
                // Nothing to do here, someone just cancelled
                debug("IMAP validation was cancelled: %s", err.message);
            } catch (GLib.Error err) {
                Geary.ErrorContext context = new Geary.ErrorContext(err);
                debug("Error validating IMAP service: %s",
                      context.format_full_error());
                this.imap_tls.show();
                to_focus = this.imap_hostname.value;
                // Translators: In-app notification label
                message = _("Check your receiving server details");
            }

            if (imap_valid) {
                debug("Validating SMTP...");
                try {
                    yield this.engine.validate_smtp(
                        account,
                        account.outgoing,
                        account.incoming.credentials,
                        cancellable
                    );
                    smtp_valid = true;
                } catch (Geary.SmtpError.AUTHENTICATION_FAILED err) {
                    debug("Error authenticating SMTP service: %s", err.message);
                    // There was an SMTP auth error, but IMAP already
                    // succeeded, so the user probably needs to
                    // specify custom creds here
                    this.smtp_auth.value.source =
                        Geary.Credentials.Requirement.CUSTOM;
                    to_focus = this.smtp_login.value;
                    // Translators: In-app notification label
                    message = _("Check your sending login and password");
                } catch (GLib.TlsError.BAD_CERTIFICATE err) {
                    // Nothing to do here, since the untrusted host
                    // handler will be dealing with it
                } catch (GLib.IOError.CANCELLED err) {
                    // Nothing to do here, someone just cancelled
                    debug("SMTP validation was cancelled: %s", err.message);
                } catch (GLib.Error err) {
                    Geary.ErrorContext context = new Geary.ErrorContext(err);
                    debug("Error validating SMTP service: %s",
                          context.format_full_error());
                    this.smtp_tls.show();
                    to_focus = this.smtp_hostname.value;
                    // Translators: In-app notification label
                    message = _("Check your sending server details");
                }
            }

            is_valid = imap_valid && smtp_valid;
        } else {
            try {
                yield this.engine.validate_imap(
                    account, account.incoming, cancellable
                );
                is_valid = true;
            } catch (Geary.ImapError.UNAUTHENTICATED err) {
                debug("Error authenticating provider: %s", err.message);
                to_focus = this.email.value;
                // Translators: In-app notification label
                message = _("Check your email address and password");
            } catch (GLib.TlsError.BAD_CERTIFICATE err) {
                // Nothing to do here, since the untrusted host
                // handler will be dealing with it
                debug("Error validating SMTP certificate: %s", err.message);
            } catch (GLib.Error err) {
                Geary.ErrorContext context = new Geary.ErrorContext(err);
                debug("Error validating SMTP service: %s",
                      context.format_full_error());
                is_valid = false;
                // Translators: In-app notification label
                message = _("Could not connect, check your network");
            }
        }

        if (is_valid) {
            try {
                yield this.accounts.create_account(account, cancellable);
                this.editor.pop();
            } catch (GLib.Error err) {
                debug("Failed to create new local account: %s", err.message);
                is_valid = false;
                // Translators: In-app notification label for a
                // generic error creating an account
                message = _("An unexpected problem occurred");
            }
        }

        account.untrusted_host.disconnect(on_untrusted_host);
        this.is_operation_running = false;

        // Focus and pop up the notification after re-sensitising
        // so it actually succeeds.
        if (!is_valid) {
            if (to_focus != null) {
                to_focus.grab_focus();
            }
            if (message != null) {
                this.editor.add_notification(
                    new Components.InAppNotification(
                        // Translators: In-app notification label, the
                        // string substitution is a more detailed reason.
                        _("Account not created: %s").printf(message)
                    )
                );
            }
        }
    }

    private Geary.ServiceInformation new_imap_service() {
        Geary.ServiceInformation service = new Geary.ServiceInformation(
            Geary.Protocol.IMAP, this.provider
        );

        service.credentials = new Geary.Credentials(
            Geary.Credentials.Method.PASSWORD,
            this.imap_login.value.get_text().strip(),
            this.imap_password.value.get_text().strip()
        );

        Components.NetworkAddressValidator host =
            (Components.NetworkAddressValidator)
            this.imap_hostname.validator;
        GLib.NetworkAddress address = host.validated_address;
        service.host = address.hostname;
        service.port = (uint16) address.port;
        service.transport_security = this.imap_tls.value.method;

        if (service.port == 0) {
            service.port = service.get_default_port();
        }

        return service;
    }

    private Geary.ServiceInformation new_smtp_service() {
        Geary.ServiceInformation service = new Geary.ServiceInformation(
            Geary.Protocol.SMTP, this.provider
        );

        service.credentials_requirement = this.smtp_auth.value.source;
        if (service.credentials_requirement ==
                Geary.Credentials.Requirement.CUSTOM) {
            service.credentials = new Geary.Credentials(
                Geary.Credentials.Method.PASSWORD,
                this.smtp_login.value.get_text().strip(),
                this.smtp_password.value.get_text().strip()
            );
        }

        Components.NetworkAddressValidator host =
            (Components.NetworkAddressValidator)
            this.smtp_hostname.validator;
        GLib.NetworkAddress address = host.validated_address;

        service.host = address.hostname;
        service.port = (uint16) address.port;
        service.transport_security = this.smtp_tls.value.method;

        if (service.port == 0) {
            service.port = service.get_default_port();
        }

        return service;
    }

    private void check_validation() {
        bool server_settings_visible = this.stack.get_visible_child_name() == "server_settings";
        bool controls_valid = true;
        Gtk.ListBox[] list_boxes;
        if (server_settings_visible) {
            list_boxes = new Gtk.ListBox[] {
                this.details_list, this.receiving_list, this.sending_list
            };
        } else {
            list_boxes = new Gtk.ListBox[] { this.details_list };
        }
        foreach (Gtk.ListBox list_box in list_boxes) {
            list_box.foreach((child) => {
                    AddPaneRow? validatable = child as AddPaneRow;
                    if (validatable != null && !validatable.validator.is_valid) {
                        controls_valid = false;
                    }
                });
        }
        this.action_button.set_sensitive(controls_valid);
        this.controls_valid = controls_valid;
    }

    private void update_operation_ui(bool is_running) {
        this.action_spinner.visible = is_running;
        this.action_spinner.active = is_running;
        this.action_button.sensitive = !is_running;
        this.back_button.sensitive = !is_running;
        this.sensitive = !is_running;
    }

    private void switch_to_user_settings() {
        this.stack.set_visible_child_name("user_settings");
        this.action_button.set_label(_("_Next"));
        this.action_button.set_sensitive(true);
        this.action_button.get_style_context().remove_class("suggested-action");
    }

    private void switch_to_server_settings() {
        this.stack.set_visible_child_name("server_settings");
        this.action_button.set_label(_("_Create"));
        this.action_button.set_sensitive(false);
        this.action_button.get_style_context().add_class("suggested-action");
    }

    private void set_server_settings_from_autoconfig(AutoConfig auto_config,
                                                     GLib.AsyncResult res)
            throws Accounts.AutoConfigError {
        AutoConfigValues auto_config_values = auto_config.get_config.end(res);
        Gtk.Entry imap_hostname_entry = this.imap_hostname.value;
        Gtk.Entry smtp_hostname_entry = this.smtp_hostname.value;
        TlsComboBox imap_tls_combo_box = this.imap_tls.value;
        TlsComboBox smtp_tls_combo_box = this.smtp_tls.value;

        imap_hostname_entry.text = auto_config_values.imap_server +
             ":" + auto_config_values.imap_port;
        smtp_hostname_entry.text = auto_config_values.smtp_server +
             ":" + auto_config_values.smtp_port;
        imap_tls_combo_box.method = auto_config_values.imap_tls_method;
        smtp_tls_combo_box.method = auto_config_values.smtp_tls_method;

        this.imap_hostname.hide();
        this.smtp_hostname.hide();
        this.imap_tls.hide();
        this.smtp_tls.hide();

        switch (auto_config_values.id) {
        case "googlemail.com":
            this.provider = Geary.ServiceProvider.GMAIL;
            break;
        case "hotmail.com":
            this.provider = Geary.ServiceProvider.OUTLOOK;
            break;
        default:
            this.provider = Geary.ServiceProvider.OTHER;
            break;
        }
    }

    private void set_server_settings_from_hostname(string hostname) {
        Gtk.Entry imap_hostname_entry = this.imap_hostname.value;
        Gtk.Entry smtp_hostname_entry = this.smtp_hostname.value;
        string smtp_hostname = "smtp." + hostname;
        string imap_hostname = "imap." + hostname;
        string last_imap_hostname = "";
        string last_smtp_hostname = "";

        this.imap_hostname.show();
        this.smtp_hostname.show();

        if (this.last_valid_hostname != "") {
            last_imap_hostname = "imap." + this.last_valid_hostname;
            last_smtp_hostname = "smtp." + this.last_valid_hostname;
        }
        if (imap_hostname_entry.text == last_imap_hostname) {
            imap_hostname_entry.text = imap_hostname;
        }
        if (smtp_hostname_entry.text == last_smtp_hostname) {
            smtp_hostname_entry.text = smtp_hostname;
        }
        this.last_valid_hostname = hostname;
    }

    private void add_goa_account() {
        this.accounts.add_goa_account.begin(
            this.provider, this.op_cancellable,
            (obj, res) => {
                bool add_local = false;
                try {
                    this.accounts.add_goa_account.end(res);
                } catch (GLib.IOError.NOT_SUPPORTED err) {
                    // Not a supported type, so don't bother logging the error
                    add_local = true;
                } catch (GLib.Error err) {
                    debug("Failed to add %s via GOA: %s",
                          this.provider.to_string(), err.message);
                    add_local = true;
                }

                if (add_local) {
                    switch_to_server_settings();
                } else {
                    this.editor.pop();
                }
            }
        );
    }

    private void on_validated(Components.Validator.Trigger reason) {
        check_validation();
        if (this.controls_valid && reason == Components.Validator.Trigger.ACTIVATED) {
            this.action_button.clicked();
        }
    }

    private void on_activated() {
        if (this.controls_valid) {
            this.action_button.clicked();
        }
    }

    private void on_email_changed() {
        Gtk.Entry imap_login_entry = this.imap_login.value;
        Gtk.Entry smtp_login_entry = this.smtp_login.value;

        this.auto_config_cancellable.cancel();

        if (this.email.validator.state != Components.Validator.Validity.VALID) {
            return;
        }

        string email = this.email.value.text;
        string hostname = email.split("@")[1];

        // Do not update entries if changed by user
        if (imap_login_entry.text == this.last_valid_email) {
            imap_login_entry.text = email;
        }
        if (smtp_login_entry.text == this.last_valid_email) {
            smtp_login_entry.text = email;
        }

        this.last_valid_email = email;

        // Try to get configuration from Thunderbird autoconfig service
        this.action_spinner.visible = true;
        this.action_spinner.active = true;
        this.auto_config_cancellable = new GLib.Cancellable();
        var auto_config = new AutoConfig(this.auto_config_cancellable);
        auto_config.get_config.begin(hostname, (obj, res) => {
            try {
                set_server_settings_from_autoconfig(auto_config, res);
            } catch (Accounts.AutoConfigError err) {
                debug("Error getting auto configuration: %s", err.message);
                set_server_settings_from_hostname(hostname);
            }
            this.action_spinner.visible = false;
            this.action_spinner.active = false;
        });
    }

    private void on_smtp_auth_changed() {
        if (this.smtp_auth.value.source == Geary.Credentials.Requirement.CUSTOM) {
            this.sending_list.add(this.smtp_login);
            this.sending_list.add(this.smtp_password);
        } else if (this.smtp_login.parent != null) {
            this.sending_list.remove(this.smtp_login);
            this.sending_list.remove(this.smtp_password);
        }
        check_validation();
    }

    private void on_untrusted_host(Geary.AccountInformation account,
                                   Geary.ServiceInformation service,
                                   Geary.Endpoint endpoint,
                                   GLib.TlsConnection cx) {
        this.editor.prompt_pin_certificate.begin(
            account, service, endpoint, this.op_cancellable,
            (obj, res) => {
                try {
                    this.editor.prompt_pin_certificate.end(res);
                } catch (Application.CertificateManagerError err) {
                    // All good, just drop back into the editor
                    // window.
                    return;
                }

                // Kick off another attempt to validate
                this.validate_account.begin(this.op_cancellable);
            });
    }

    [GtkCallback]
    private void on_action_button_clicked() {
        if (this.stack.get_visible_child_name() == "user_settings") {
            switch (this.provider) {
            case Geary.ServiceProvider.GMAIL:
            case Geary.ServiceProvider.OUTLOOK:
                add_goa_account();
                break;
            case Geary.ServiceProvider.OTHER:
                switch_to_server_settings();
                break;
            }
        } else {
            this.validate_account.begin(this.op_cancellable);
        }
    }

    [GtkCallback]
    private void on_back_button_clicked() {
        if (this.stack.get_visible_child_name() == "user_settings") {
            this.editor.pop();
        } else {
            switch_to_user_settings();
        }
    }

    [GtkCallback]
    private bool on_list_keynav_failed(Gtk.Widget widget,
                                       Gtk.DirectionType direction) {
        bool ret = Gdk.EVENT_PROPAGATE;
        Gtk.Container? next = null;
        if (direction == Gtk.DirectionType.DOWN) {
            if (widget == this.details_list) {
                debug("Have details!");
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

}


private abstract class Accounts.AddPaneRow<Value> :
    LabelledEditorRow<EditorAddPane,Value> {


    internal Components.Validator? validator { get; protected set; }


    protected AddPaneRow(string label, Value value) {
        base(label, value);
        this.activatable = false;
    }

}


private abstract class Accounts.EntryRow : AddPaneRow<Gtk.Entry> {


    private Components.EntryUndo undo;


    protected EntryRow(string label,
                       string? initial_value = null,
                       string? placeholder = null) {
        base(label, new Gtk.Entry());

        this.value.text = initial_value ?? "";
        this.value.placeholder_text = placeholder ?? "";
        this.value.width_chars = 16;

        this.undo = new Components.EntryUndo(this.value);
    }

    public override bool focus(Gtk.DirectionType direction) {
        bool ret = Gdk.EVENT_PROPAGATE;
        switch (direction) {
        case Gtk.DirectionType.TAB_FORWARD:
        case Gtk.DirectionType.TAB_BACKWARD:
            ret = this.value.child_focus(direction);
            break;

        default:
            ret = base.focus(direction);
            break;
        }

        return ret;
    }

}


private class Accounts.NameRow : EntryRow {

    public NameRow(string default_name) {
        // Translators: Label for the person's actual name when adding
        // an account
        base(_("Your name"), default_name.strip());
        this.validator = new Components.Validator(this.value);
        if (this.value.text != "") {
            // Validate if the string is non-empty so it will be good
            // to go from the start
            this.validator.validate();
        }
    }

}


private class Accounts.EmailRow : EntryRow {


    public EmailRow() {
        base(
            _("Email address"),
            null,
            // Translators: Placeholder for the default sender address
            // when adding an account
            _("person@example.com")
        );
        this.value.input_purpose = Gtk.InputPurpose.EMAIL;
        this.validator = new Components.EmailValidator(this.value);
    }

}


private class Accounts.LoginRow : EntryRow {

    public LoginRow() {
        // Translators: Label for an IMAP/SMTP service login/user name
        // when adding an account
        base(_("Login name"));
        // Logins are not infrequently the same as the user's email
        // address
        this.value.input_purpose = Gtk.InputPurpose.EMAIL;
        this.validator = new Components.Validator(this.value);
    }

}


private class Accounts.PasswordRow : EntryRow {


    public PasswordRow() {
        base(_("Password"));
        this.value.visibility = false;
        this.value.input_purpose = Gtk.InputPurpose.PASSWORD;
        this.validator = new Components.Validator(this.value);
    }

}


private class Accounts.HostnameRow : EntryRow {


    private Geary.Protocol type;


    public HostnameRow(Geary.Protocol type) {
        string label = "";
        string placeholder = "";
        switch (type) {
        case Geary.Protocol.IMAP:
            // Translators: Label for the IMAP server hostname when
            // adding an account.
            label = _("IMAP server");
            // Translators: Placeholder for the IMAP server hostname
            // when adding an account.
            placeholder = _("imap.example.com");
            break;

        case Geary.Protocol.SMTP:
            // Translators: Label for the SMTP server hostname when
            // adding an account.
            label = _("SMTP server");
            // Translators: Placeholder for the SMTP server hostname
            // when adding an account.
            placeholder = _("smtp.example.com");
            break;
        }

        base(label, null, placeholder);
        this.type = type;

        this.validator = new Components.NetworkAddressValidator(this.value, 0);
    }

}


private class Accounts.TransportSecurityRow :
    LabelledEditorRow<EditorAddPane,TlsComboBox> {

    public TransportSecurityRow() {
        TlsComboBox value = new TlsComboBox();
        base(value.label, value);
        // Set to Transport TLS by default per RFC 8314
        this.value.method = Geary.TlsNegotiationMethod.TRANSPORT;
    }

}


private class Accounts.OutgoingAuthRow :
    LabelledEditorRow<EditorAddPane,OutgoingAuthComboBox> {

    public OutgoingAuthRow() {
        OutgoingAuthComboBox value = new OutgoingAuthComboBox();
        base(value.label, value);

        this.activatable = false;
        this.value.source = Geary.Credentials.Requirement.USE_INCOMING;
    }

}
