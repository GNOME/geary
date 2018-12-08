/*
 * Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* GNOME Online Accounts token adapter. */
public class GoaMediator : Geary.CredentialsMediator, Object {


    public bool is_valid {
        get {
            Goa.Account account = this.account.get_account();
            // Goa.Account.mail_disabled doesn't seem to reflect if we
            // get can get a valid mail object or not, so just rely on
            // actually getting one instead.
            Goa.Mail? mail = this.account.get_mail();
            return (
                mail != null &&
                !account.attention_needed &&
                (this.oauth2 != null || this.password != null)
            );
        }
    }

    public Geary.Credentials.Method method {
        get {
            Geary.Credentials.Method method = Geary.Credentials.Method.PASSWORD;
            if (this.oauth2 != null) {
                method = Geary.Credentials.Method.OAUTH2;
            }
            return method;
        }
    }

    private Goa.Object account;
    private Goa.OAuth2Based? oauth2 = null;
    private Goa.PasswordBased? password = null;


    public GoaMediator(Goa.Object account) {
        this.account = account;
    }

    public Geary.ServiceProvider get_service_provider() {
        Geary.ServiceProvider provider = Geary.ServiceProvider.OTHER;
        switch (this.account.get_account().provider_type) {
        case "google":
            provider = Geary.ServiceProvider.GMAIL;
            break;

        case "windows_live":
            provider = Geary.ServiceProvider.OUTLOOK;
            break;
        }
        return provider;
    }

    public string get_service_label() {
        return this.account.get_account().provider_name;
    }

    public async void update(Geary.AccountInformation geary_account,
                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        // XXX have to call the sync version of this since the async
        // version seems to be broken
        this.account.get_account().call_ensure_credentials_sync(
            null, cancellable
        );
        this.oauth2 = this.account.get_oauth2_based();
        this.password = this.account.get_password_based();

        update_imap_config(geary_account.incoming);
        update_smtp_config(geary_account.outgoing);
    }

    public virtual async bool load_token(Geary.AccountInformation account,
                                         Geary.ServiceInformation service,
                                         Cancellable? cancellable)
        throws GLib.Error {
        bool loaded = false;
        string? token = null;

        if (this.method == Geary.Credentials.Method.OAUTH2) {
            // XXX have to call the sync version of this since the async
            // version seems to be broken
            this.oauth2.call_get_access_token_sync(
                out token, null, cancellable
            );
        } else {
            // XXX have to call the sync version of these since the
            // async version seems to be broken
            switch (service.protocol) {
            case Geary.Protocol.IMAP:
                this.password.call_get_password_sync(
                    "imap-password", out token, cancellable
                );
                break;

            case Geary.Protocol.SMTP:
                this.password.call_get_password_sync(
                    "smtp-password", out token, cancellable
                );
                break;

            default:
                return false;
            }
        }

        if (token != null) {
            service.credentials = service.credentials.copy_with_token(token);
            loaded = true;
        }
        return loaded;
    }

    public virtual async bool prompt_token(Geary.AccountInformation account,
                                           Geary.ServiceInformation service,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Prompt GOA to update the creds. This might involve some
        // user interaction.
        yield update(account, cancellable);

        // XXX now open a dialog that says "Click here to change your
        // GOA password" or "GOA credentials need renewing" or
        // something. Connect to the GOA service and wait until we
        // hear that needs attention is no longer true.

        return this.is_valid;
    }

    private void update_imap_config(Geary.ServiceInformation service) {
        Goa.Mail? mail = this.account.get_mail();
        if (mail != null) {
            parse_host_name(service, mail.imap_host);

            if (mail.imap_use_ssl) {
                service.transport_security = Geary.TlsNegotiationMethod.TRANSPORT;
            } else if (mail.imap_use_tls) {
                service.transport_security = Geary.TlsNegotiationMethod.START_TLS;
            } else {
                service.transport_security = Geary.TlsNegotiationMethod.NONE;
            }

            service.credentials = new Geary.Credentials(
                this.method, mail.imap_user_name
            );

            if (service.port == 0) {
                service.port = service.get_default_port();
            }
        }
    }

    private void update_smtp_config(Geary.ServiceInformation service) {
        Goa.Mail? mail = this.account.get_mail();
        if (mail != null) {
            parse_host_name(service, mail.smtp_host);

            if (mail.imap_use_ssl) {
                service.transport_security = Geary.TlsNegotiationMethod.TRANSPORT;
            } else if (mail.imap_use_tls) {
                service.transport_security = Geary.TlsNegotiationMethod.START_TLS;
            } else {
                service.transport_security = Geary.TlsNegotiationMethod.NONE;
            }

            if (mail.smtp_use_auth) {
                service.credentials_requirement = Geary.Credentials.Requirement.CUSTOM;
            } else {
                service.credentials_requirement = Geary.Credentials.Requirement.NONE;
            }

            if (mail.smtp_use_auth) {
                service.credentials = new Geary.Credentials(
                    this.method, mail.smtp_user_name
                );
            }

            if (service.port == 0) {
                service.port = service.get_default_port();
            }
        }
    }

    private void parse_host_name(Geary.ServiceInformation service,
                                 string host_name) {
        // Fall back to trying to use the host name as-is.
        // At least the user can see it in the settings if
        // they look.
        service.host = host_name;
        service.port = 0;

        try {
            GLib.NetworkAddress address = GLib.NetworkAddress.parse(
                host_name, service.port
            );

            service.host = address.hostname;
            service.port = (uint16) address.port;
        } catch (GLib.Error err) {
            warning(
                "GOA account \"%s\" %s hostname \"%s\": %",
                this.account.get_account().id,
                service.protocol.to_value(),
                host_name,
                err.message
            );
        }
    }

}
