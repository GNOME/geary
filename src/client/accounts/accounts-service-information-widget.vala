/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget for editing a {@link Geary.ServiceInformation} object.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts-service-information-widget.ui")]
internal class Accounts.ServiceInformationWidget : Adw.PreferencesGroup {

    public Geary.ServiceInformation service {
        get { return this._service; }
        set {
            this._service = value;
            this.service_mutable = new Geary.ServiceInformation.copy(value);
            update_details();
            value.notify.connect((obj, pspec) => { update_details(); });
        }
    }
    private Geary.ServiceInformation _service;

    // A copy of the original that can be without breaking the original
    public Geary.ServiceInformation service_mutable { get ; private set; }

    public Components.ValidatorGroup validators { get; construct set; }

    [GtkChild] private unowned Adw.EntryRow host_row;
    [GtkChild] private unowned TlsComboRow security_row;
    [GtkChild] private unowned Adw.ComboRow credentials_requirement_row;
    [GtkChild] private unowned Adw.EntryRow login_name_row;
    [GtkChild] private unowned Adw.PasswordEntryRow password_row;


    static construct {
        typeof(TlsComboRow).ensure();
        typeof(Components.ValidatorGroup).ensure();
        typeof(Components.Validator).ensure();
    }


    /**
     * Sets whether editing the information is possible
     */
    public void set_editable(bool editable) {
        this.sensitive = editable;
        update_details();
    }

    private void update_details() {
        update_host_row(this.host_row, this.service_mutable);
        this.security_row.method = this.service_mutable.transport_security;
        update_auth(this.service_mutable);
    }

    private void update_host_row(Adw.EntryRow row, Geary.ServiceInformation service) {
        row.title = host_label_for_protocol(service.protocol);

        row.text = service.host ?? "";
        if (!Geary.String.is_empty(service.host)) {
            // Only show the port if it not the appropriate default port
            uint16 port = service.port;
            if (port != service.get_default_port()) {
                row.text = "%s:%d".printf(service.host, service.port);
            }
        }
    }

    private string host_label_for_protocol(Geary.Protocol protocol) {
        switch (protocol) {
        case Geary.Protocol.IMAP:
            // Translators: This label describes the host name or IP
            // address and port used by an account's IMAP service.
            return _("IMAP Server");

        case Geary.Protocol.SMTP:
            // Translators: This label describes the host name or IP
            // address and port used by an account's SMTP service.
            return _("SMTP Server");
        }

        return _("Unknown Protocol");
    }

    private void update_login_name_row(Adw.EntryRow row,
                                       Geary.ServiceInformation service) {
        // Translators: Label used when no auth scheme is used
        // by an account's IMAP or SMTP service.
        row.text = _("None");

        // If we have credentials, we can do better
        if (service.credentials != null) {
            switch (service.credentials.supported_method) {
            case Geary.Credentials.Method.PASSWORD:
                row.text = service.credentials.user;
                break;

            case Geary.Credentials.Method.OAUTH2:
                // Add a suffix for OAuth2 auth so people know they
                // shouldn't expect to be prompted for a password

                // Translators: Label used when an account's IMAP or
                // SMTP service uses OAuth2. The string replacement is
                // the service's login name.
                row.text = _("%s using OAuth2").printf(service.credentials.user ?? "");
                break;
            }
        }

        // If we rely on the credentials of the incoming server, notify the user of that
        if (service.protocol == Geary.Protocol.SMTP &&
                   service.credentials_requirement ==
                   Geary.Credentials.Requirement.USE_INCOMING) {
            row.text = _("Use receiving server login");
        }
    }

    private void update_password_row(Adw.PasswordEntryRow row,
                                     Geary.ServiceInformation service) {
        if (service.credentials != null) {
            row.text = service.credentials.token ?? "";
        } else {
            row.text = "";
        }

        // If we're not enabled, the "Show Password" button is insensitive too
        // so just hide the row
        if (!this.sensitive)
            row.visible = false;
    }

    [GtkCallback]
    private void on_host_row_changed(Gtk.Editable editable) {
    }

    private void update_auth(Geary.ServiceInformation service) {
        bool is_smtp = (service.protocol == Geary.Protocol.SMTP);
        this.credentials_requirement_row.visible = is_smtp;

        if (is_smtp) {
            this.credentials_requirement_row.selected = service.credentials_requirement;

            bool needs_login =
                (service.credentials_requirement == Geary.Credentials.Requirement.CUSTOM);
            this.login_name_row.visible = needs_login;
            this.password_row.visible = needs_login;
        }

        update_login_name_row(this.login_name_row, this.service_mutable);
        update_password_row(this.password_row, this.service_mutable);
    }

    [GtkCallback]
    private static string outgoing_auth_to_string(Adw.EnumListItem item,
                                                  Geary.Credentials.Requirement requirement) {
        return requirement.to_string();
    }

    [GtkCallback]
    private void on_validators_changed(Components.ValidatorGroup validators,
                                       Components.Validator validator) {
        //XXX what do we do here?
    }

    [GtkCallback]
    private void on_validators_activated(Components.ValidatorGroup validators,
                                         Components.Validator validator) {
        //XXX what do we do here?
    }
}
