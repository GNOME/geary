/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* A local service implementation. This loads and saves IMAP and SMTP settings
 * from and to an account's configuration file. */
public class LocalServiceInformation : Geary.ServiceInformation {


    private const string HOST = "host";
    private const string PORT = "port";
    private const string REMEMBER_PASSWORD_KEY = "remember_password";
    private const string SMTP_NOAUTH = "noauth";
    private const string SMTP_USE_IMAP_CREDENTIALS = "use_imap_credentials";
    private const string SSL = "ssl";
    private const string STARTTLS = "starttls";
    private const string USERNAME_KEY = "username";


    public LocalServiceInformation(Geary.Protocol protocol,
                                   Geary.CredentialsMediator mediator) {
        base(protocol, mediator);
    }

    public override Geary.ServiceInformation temp_copy() {
        LocalServiceInformation copy = new LocalServiceInformation(
            this.protocol, this.mediator
        );
        copy.copy_from(this);
        return copy;
    }

    public void load_credentials(Geary.ConfigFile.Group config,
                                 Geary.Credentials.Method method,
                                 string default_login) {
        this.credentials = new Geary.Credentials(
            method, config.get_string(USERNAME_KEY, default_login)
        );
        this.remember_password = config.get_bool(
            REMEMBER_PASSWORD_KEY, this.remember_password
        );
    }

    public void load_settings(Geary.ConfigFile.Group config) {
        this.host = config.get_string(HOST, this.host);
        this.port = config.get_uint16(PORT, this.port);
        this.use_ssl = config.get_bool(SSL, this.use_ssl);
        this.use_starttls = config.get_bool(STARTTLS, this.use_starttls);

        if (this.protocol == Geary.Protocol.SMTP) {
            this.smtp_noauth = config.get_bool(
                SMTP_NOAUTH, this.smtp_noauth
            );
            this.smtp_use_imap_credentials = config.get_bool(
                SMTP_USE_IMAP_CREDENTIALS,
                this.smtp_use_imap_credentials
            );
            if (this.smtp_noauth || this.smtp_use_imap_credentials) {
                this.credentials = null;
            }
        }

    }

    public void save_settings(Geary.ConfigFile.Group config) {
        config.set_string(HOST, this.host);
        config.set_int(PORT, this.port);
        config.set_bool(SSL, this.use_ssl);
        config.set_bool(STARTTLS, this.use_starttls);
        config.set_bool(REMEMBER_PASSWORD_KEY, this.remember_password);

        if (this.credentials != null) {
            config.set_string(USERNAME_KEY, this.credentials.user);
        }

        if (this.protocol == Geary.Protocol.SMTP) {
            config.set_bool(SMTP_USE_IMAP_CREDENTIALS, this.smtp_use_imap_credentials);
            config.set_bool(SMTP_NOAUTH, this.smtp_noauth);
        }
    }

}
