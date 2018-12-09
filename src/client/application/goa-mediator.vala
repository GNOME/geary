/*
 * Copyright 2017 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** GNOME Online Accounts token adapter. */
public class GoaMediator : Geary.CredentialsMediator, Object {


    public bool is_available {
        get {
            // Goa.Account.mail_disabled doesn't seem to reflect if we
            // get can get a valid mail object or not, so just rely on
            // actually getting one instead.
            return this.handle.get_mail() != null;
        }
    }

    private Goa.Object handle;


    public GoaMediator(Goa.Object handle) {
        this.handle = handle;
    }

    public Geary.ServiceProvider get_service_provider() {
        Geary.ServiceProvider provider = Geary.ServiceProvider.OTHER;
        switch (this.handle.get_account().provider_type) {
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
        return this.handle.get_account().provider_name;
    }

    public async void update(Geary.AccountInformation geary_account,
                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        debug("checking auth");
        // Call this to get the exception thrown if no auth method is
        // supported.
        get_auth_method();

        debug("updating imap");
        update_imap_config(geary_account.incoming);
        debug("updating smtp");
        update_smtp_config(geary_account.outgoing);
        debug("updating done");
    }

    public virtual async bool load_token(Geary.AccountInformation account,
                                         Geary.ServiceInformation service,
                                         Cancellable? cancellable)
        throws GLib.Error {
        // XXX have to call the sync version of this since the async
        // version seems to be broken. See
        // https://gitlab.gnome.org/GNOME/vala/issues/709
        this.handle.get_account().call_ensure_credentials_sync(
            null, cancellable
        );

        bool loaded = false;
        string? token = null;

        switch (get_auth_method()) {
        case OAUTH2:
            this.handle.get_oauth2_based().call_get_access_token_sync(
                out token, null, cancellable
            );
            break;

        case PASSWORD:
            switch (service.protocol) {
            case Geary.Protocol.IMAP:
                this.handle.get_password_based().call_get_password_sync(
                    "imap-password", out token, cancellable
                );
                break;

            case Geary.Protocol.SMTP:
                this.handle.get_password_based().call_get_password_sync(
                    "smtp-password", out token, cancellable
                );
                break;

            default:
                return false;
            }
            break;
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

        return this.is_available;
    }

    private Geary.Credentials.Method get_auth_method() throws GLib.Error {
        if (this.handle.get_oauth2_based() != null) {
            return Geary.Credentials.Method.OAUTH2;
        }
        if (this.handle.get_password_based() != null) {
            return Geary.Credentials.Method.PASSWORD;
        }
        throw new Geary.EngineError.UNSUPPORTED(
            "GOA account supports neither password or OAuth2 auth"
        );
    }

    private void update_imap_config(Geary.ServiceInformation service)
        throws GLib.Error {
        Goa.Mail? mail = this.handle.get_mail();
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
                get_auth_method(), mail.imap_user_name
            );

            if (service.port == 0) {
                service.port = service.get_default_port();
            }
        }
    }

    private void update_smtp_config(Geary.ServiceInformation service)
        throws GLib.Error {
        Goa.Mail? mail = this.handle.get_mail();
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
                    get_auth_method(), mail.smtp_user_name
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
                this.handle.get_account().id,
                service.protocol.to_value(),
                host_name,
                err.message
            );
        }
    }

}
