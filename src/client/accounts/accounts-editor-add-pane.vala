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


    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Grid pane_content;

    [GtkChild]
    private Gtk.Adjustment pane_adjustment;

    [GtkChild]
    private Gtk.ListBox details_list;

    [GtkChild]
    private Gtk.Grid receiving_panel;

    [GtkChild]
    private Gtk.ListBox receiving_list;

    [GtkChild]
    private Gtk.Grid sending_panel;

    [GtkChild]
    private Gtk.ListBox sending_list;

    [GtkChild]
    private Gtk.Button create_button;

    [GtkChild]
    private Gtk.Button back_button;

    [GtkChild]
    private Gtk.Spinner create_spinner;

    private NameRow real_name;
    private EmailRow email = new EmailRow();
    private string last_valid_email = "";

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


    internal EditorAddPane(Editor editor, Geary.ServiceProvider provider) {
        this.editor = editor;
        this.provider = provider;

        this.accounts = editor.application.controller.account_manager;
        this.engine = editor.application.engine;

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.details_list.set_header_func(Editor.seperator_headers);
        this.receiving_list.set_header_func(Editor.seperator_headers);
        this.sending_list.set_header_func(Editor.seperator_headers);

        if (provider != Geary.ServiceProvider.OTHER) {
            this.details_list.add(
                new ServiceProviderRow<EditorAddPane>(
                    provider,
                    // Translators: Label for adding an email account
                    // account for a generic IMAP service provider.
                    _("All others")
                )
            );
            this.receiving_panel.hide();
            this.sending_panel.hide();
        }

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

        if (provider == Geary.ServiceProvider.OTHER) {
            this.receiving_list.add(this.imap_hostname);
            this.receiving_list.add(this.imap_tls);
            this.receiving_list.add(this.imap_login);
            this.receiving_list.add(this.imap_password);

            this.sending_list.add(this.smtp_hostname);
            this.sending_list.add(this.smtp_tls);
            this.sending_list.add(this.smtp_auth);
        } else {
            this.details_list.add(this.imap_password);
        }
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

        if (this.provider == Geary.ServiceProvider.OTHER) {
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
                debug("Error validating IMAP certifiate: %s", err.message);
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
                debug("Error validating SMTP certifiate: %s", err.message);
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

        if (this.provider == Geary.ServiceProvider.OTHER) {
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
        } else {
            service.credentials = new Geary.Credentials(
                Geary.Credentials.Method.PASSWORD,
                this.email.value.get_text().strip(),
                this.imap_password.value.get_text().strip()
            );
        }

        return service;
    }

    private Geary.ServiceInformation new_smtp_service() {
        Geary.ServiceInformation service = new Geary.ServiceInformation(
            Geary.Protocol.SMTP, this.provider
        );

        if (this.provider == Geary.ServiceProvider.OTHER) {
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
        }

        return service;
    }

    private void check_validation() {
        bool controls_valid = true;
        foreach (Gtk.ListBox list in new Gtk.ListBox[] {
                this.details_list, this.receiving_list, this.sending_list
            }) {
            list.foreach((child) => {
                    AddPaneRow? validatable = child as AddPaneRow;
                    if (validatable != null && !validatable.validator.is_valid) {
                        controls_valid = false;
                    }
                });
        }
        this.create_button.set_sensitive(controls_valid);
        this.controls_valid = controls_valid;
    }

    private void update_operation_ui(bool is_running) {
        this.create_spinner.visible = is_running;
        this.create_spinner.active = is_running;
        this.create_button.sensitive = !is_running;
        this.back_button.sensitive = !is_running;
        this.sensitive = !is_running;
    }

    private void on_validated(Components.Validator.Trigger reason) {
        check_validation();
        if (this.controls_valid && reason == Components.Validator.Trigger.ACTIVATED) {
            this.create_button.clicked();
        }
    }

    private void on_activated() {
        if (this.controls_valid) {
            this.create_button.clicked();
        }
    }

    private void on_email_changed() {
        string email = "";
        if (this.email.validator.state == Components.Validator.Validity.VALID) {
            email = this.email.value.text;
        }

        if (this.imap_login.value.text == this.last_valid_email) {
            this.imap_login.value.text = email;
        }
        if (this.smtp_login.value.text == this.last_valid_email) {
            this.smtp_login.value.text = email;
        }

        this.last_valid_email = email;
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
    private void on_create_button_clicked() {
        this.validate_account.begin(this.op_cancellable);
    }

    [GtkCallback]
    private void on_back_button_clicked() {
        this.editor.pop();
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
        base(label, new Gtk.Entry());
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
        this.value.width_chars = 32;

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
            this.value.activate();
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
