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
internal class Accounts.EditorAddPane : Accounts.EditorPane {


    /** {@inheritDoc} */
    internal override bool is_operation_running {
        get { return !this.sensitive; }
        protected set { update_operation_ui(value); }
    }

    /** {@inheritDoc} */
    internal override Cancellable? op_cancellable {
        get; protected set; default = new GLib.Cancellable();
    }

    protected override weak Accounts.Editor editor { get; set; }

    private Geary.ServiceProvider provider;

    private Manager accounts;
    private Geary.Engine engine;


    [GtkChild] private unowned Adw.HeaderBar header;

    [GtkChild] private unowned Gtk.Stack stack;

    [GtkChild] private unowned Adw.PreferencesGroup details_list;
    [GtkChild] private unowned Adw.EntryRow name_row;
    [GtkChild] private unowned Adw.EntryRow email_row;
    [GtkChild] private unowned Components.Validator email_validator;

    [GtkChild] private unowned ServiceInformationWidget receiving_service_widget;
    [GtkChild] private unowned ServiceInformationWidget sending_service_widget;

    [GtkChild] private unowned Gtk.Button action_button;
    [GtkChild] private unowned Adw.Spinner action_spinner;

    private string last_valid_email = "";
    private string last_valid_hostname = "";

    //XXX if this is set, we shuld hide the IMAP/SMTP hostnames/auth
    private bool did_auto_config { get; private set; default = false; }
    private GLib.Cancellable auto_config_cancellable = new GLib.Cancellable();

    private bool controls_valid = false;

    public Components.ValidatorGroup validators { get; construct set; }


    static construct {
        typeof(Components.ValidatorGroup).ensure();
        typeof(Components.Validator).ensure();
        typeof(Components.EmailValidator).ensure();
    }

    internal EditorAddPane(Editor editor) {
        Object(editor: editor);

        this.provider = Geary.ServiceProvider.OTHER;

        this.accounts = editor.application.controller.account_manager;
        this.engine = editor.application.engine;

        this.name_row.text = this.accounts.get_account_name();
        //XXX GTK4 make sure it's validated immediately

        this.receiving_service_widget.service = new_imap_service();
        this.sending_service_widget.service = new_smtp_service();

        // XXX we need to make sure the validators for the service are wired up too
        // this.smtp_auth.value.changed.connect(on_smtp_auth_changed);
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
                    this.name_row.text.strip(),
                    this.email_row.text.strip()
                ),
                cancellable
            );

        account.incoming = this.receiving_service_widget.service_mutable;
        account.outgoing = this.sending_service_widget.service_mutable;
        account.untrusted_host.connect(on_untrusted_host);

        if (this.provider == Geary.ServiceProvider.OTHER &&
                !this.did_auto_config) {
            bool imap_valid = false;
            bool smtp_valid = false;

            try {
                yield this.engine.validate_imap(
                    account, account.incoming, cancellable
                );
                imap_valid = true;
            } catch (Geary.ImapError.UNAUTHENTICATED err) {
                debug("Error authenticating IMAP service: %s", err.message);
                to_focus = this.receiving_service_widget;
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
                //XXX GTK4 not sure how to design a nice API for this
                // this.imap_tls.show();
                to_focus = this.receiving_service_widget;
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
                    this.receiving_service_widget.service.credentials_requirement =
                        Geary.Credentials.Requirement.CUSTOM;
                    to_focus = this.receiving_service_widget;
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
                    to_focus = this.sending_service_widget;
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
                to_focus = this.email_row;
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
                this.editor.pop_pane();
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
                this.editor.add_toast(
                    new Adw.Toast(
                        // Translators: In-app notification label, the
                        // string substitution is a more detailed reason.
                        _("Account not created: %s").printf(message)
                    )
                );
            }
        }
    }

    private Geary.ServiceInformation new_imap_service() {
        var service = new Geary.ServiceInformation(
            Geary.Protocol.IMAP, this.provider
        );
        service.credentials = new Geary.Credentials(
            Geary.Credentials.Method.PASSWORD, ""
        );
        return service;
    }

    private Geary.ServiceInformation new_smtp_service() {
        return new Geary.ServiceInformation(
            Geary.Protocol.SMTP, this.provider
        );
    }

    private void check_validation() {
#if 0
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
            for (int i = 0; true; i++) {
                unowned var validatable = list_box.get_row_at_index(i) as AddPaneRow;
                if (validatable == null)
                    break;
                if (!validatable.validator.is_valid) {
                    controls_valid = false;
                }
            }
        }
        this.action_button.set_sensitive(controls_valid);
        this.controls_valid = controls_valid;
#endif
    }

    private void update_operation_ui(bool is_running) {
        this.action_spinner.visible = is_running;
        this.action_button.sensitive = !is_running;
        this.sensitive = !is_running;
    }

    private void switch_to_user_settings() {
        this.stack.set_visible_child_name("user_settings");
        this.action_button.set_label(_("_Next"));
        this.action_button.set_sensitive(true);
        this.action_button.remove_css_class("suggested-action");
    }

    private void switch_to_server_settings() {
        this.stack.set_visible_child_name("server_settings");
        this.action_button.set_label(_("_Create"));
        this.action_button.set_sensitive(false);
        this.action_button.add_css_class("suggested-action");
    }

    private void set_server_settings_from_autoconfig(AutoConfig auto_config,
                                                     GLib.AsyncResult res)
            throws Accounts.AutoConfigError {
        AutoConfigValues auto_config_values = auto_config.get_config.end(res);

        Geary.ServiceInformation imap_service = this.receiving_service_widget.service;
        Geary.ServiceInformation smtp_service = this.sending_service_widget.service;

        imap_service.host = auto_config_values.imap_server;
        imap_service.port = (uint16) uint.parse(auto_config_values.imap_port);
        imap_service.transport_security = auto_config_values.imap_tls_method;

        smtp_service.host = auto_config_values.smtp_server;
        smtp_service.port = (uint16) uint.parse(auto_config_values.smtp_port);
        smtp_service.transport_security = auto_config_values.smtp_tls_method;

        //XXX GTK4 hide servr rows
        // this.imap_hostname.hide();
        // this.smtp_hostname.hide();
        // this.imap_tls.hide();
        // this.smtp_tls.hide();

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
        Geary.ServiceInformation imap_service = this.receiving_service_widget.service;
        Geary.ServiceInformation smtp_service = this.sending_service_widget.service;
        string smtp_hostname = "smtp." + hostname;
        string imap_hostname = "imap." + hostname;
        string last_imap_hostname = "";
        string last_smtp_hostname = "";

        // XXX GTK4 show these again if an autoconf happened
        // this.imap_hostname.show();
        // this.smtp_hostname.show();

        if (this.last_valid_hostname != "") {
            last_imap_hostname = "imap." + this.last_valid_hostname;
            last_smtp_hostname = "smtp." + this.last_valid_hostname;
        }
        if (imap_service.host == last_imap_hostname) {
            imap_service.host = imap_hostname;
        }
        if (smtp_service.host == last_smtp_hostname) {
            smtp_service.host = smtp_hostname;
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
                    this.editor.pop_pane();
                }
            }
        );
    }

    [GtkCallback]
    private void on_validated(Components.ValidatorGroup validators,
                              Components.Validator validator) {
        check_validation();
        //XXX GTK4 we somehow lost the Validator.Trigger here
        // if (this.controls_valid && reason == Components.Validator.Trigger.ACTIVATED) {
        //     this.action_button.clicked();
        // }
    }

    [GtkCallback]
    private void on_activated() {
        if (this.controls_valid) {
            this.action_button.clicked();
        }
    }

    [GtkCallback]
    private void on_email_row_changed(Gtk.Editable editable) {
        var imap_service = this.receiving_service_widget.service;
        var smtp_service = this.sending_service_widget.service;

        this.auto_config_cancellable.cancel();

        if (this.email_validator.state != Components.Validator.Validity.VALID) {
            return;
        }

        string email = this.email_row.text;
        string hostname = email.split("@")[1];

        // Do not update entries if changed by user
        if (imap_service.credentials.user == this.last_valid_email) {
            imap_service.credentials = new Geary.Credentials(
                Geary.Credentials.Method.PASSWORD, email
            );
        }
        if (smtp_service.credentials.user == this.last_valid_email) {
            smtp_service.credentials = new Geary.Credentials(
                Geary.Credentials.Method.PASSWORD, email
            );
        }

        this.last_valid_email = email;

        // Try to get configuration from Thunderbird autoconfig service
        this.action_spinner.visible = true;
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
        });
    }

    private void on_smtp_auth_changed() {
#if 0
        if (this.smtp_auth.value.source == Geary.Credentials.Requirement.CUSTOM) {
            this.sending_list.append(this.smtp_login);
            this.sending_list.append(this.smtp_password);
        } else if (this.smtp_login.parent != null) {
            this.sending_list.remove(this.smtp_login);
            this.sending_list.remove(this.smtp_password);
        }
        check_validation();
#endif
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
}
