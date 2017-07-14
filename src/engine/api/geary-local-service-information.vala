/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* A local service implementation. This loads and saves IMAP and SMTP settings
 * from and to an account's configuration file. */
public class Geary.LocalServiceInformation : Geary.ServiceInformation {

    // The account's configuration file.
    private File file;

    public LocalServiceInformation(Geary.Service service,
                                   File config_directory,
                                   Geary.CredentialsMediator? mediator) {
        this.service = service;
        this.file = config_directory.get_child(Geary.AccountInformation.SETTINGS_FILENAME);
        this.mediator = mediator;
        this.credentials_method = "METHOD_LIBSECRET";
    }

    public override void load_settings(KeyFile? key_file = null) throws Error {
        string host_key = "";
        string port_key = "";
        string use_ssl_key = "";
        string use_starttls_key = "";
        uint16 default_port = 0;

        key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);

        switch (service) {
            case Geary.Service.IMAP:
                host_key = Geary.Config.IMAP_HOST;
                port_key = Geary.Config.IMAP_PORT;
                use_ssl_key = Geary.Config.IMAP_SSL;
                use_starttls_key = Geary.Config.IMAP_STARTTLS;
                default_port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL;
                break;
            case Geary.Service.SMTP:
                host_key = Geary.Config.SMTP_HOST;
                port_key = Geary.Config.SMTP_PORT;
                use_ssl_key = Geary.Config.SMTP_SSL;
                use_starttls_key = Geary.Config.SMTP_STARTTLS;
                default_port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL;
                this.smtp_noauth = Geary.Config.get_bool_value(
                    key_file, Geary.Config.GROUP, Geary.Config.SMTP_NOAUTH, this.smtp_noauth);
                if (smtp_noauth)
                    credentials = null;
                this.smtp_use_imap_credentials = Geary.Config.get_bool_value(
                    key_file, Geary.Config.GROUP, Geary.Config.SMTP_USE_IMAP_CREDENTIALS, this.smtp_use_imap_credentials);
                break;
        }

        this.host = Geary.Config.get_string_value(
            key_file, Geary.Config.GROUP, host_key, this.host);
        this.port = Geary.Config.get_uint16_value(
            key_file, Geary.Config.GROUP, port_key, default_port);
        this.use_ssl = Geary.Config.get_bool_value(
            key_file, Geary.Config.GROUP, use_ssl_key, this.use_ssl);
        this.use_starttls = Geary.Config.get_bool_value(
            key_file, Geary.Config.GROUP, use_starttls_key, this.use_starttls);
    }

    public override void load_credentials(KeyFile? key_file = null, string? email_address = null) throws Error {
        string remember_password_key = "";
        string username_key = "";

        key_file.load_from_file(file.get_path() ?? "", KeyFileFlags.NONE);

        switch (this.service) {
            case Geary.Service.IMAP:
                username_key = Geary.Config.IMAP_USERNAME_KEY;
                remember_password_key = Geary.Config.IMAP_REMEMBER_PASSWORD_KEY;
                break;
            case Geary.Service.SMTP:
                username_key = Geary.Config.SMTP_USERNAME_KEY;
                remember_password_key = Geary.Config.SMTP_REMEMBER_PASSWORD_KEY;
                break;
        }

        this.credentials.user = Geary.Config.get_string_value(
            key_file, Geary.Config.GROUP, username_key, email_address);
        this.remember_password = Geary.Config.get_bool_value(
            key_file, Geary.Config.GROUP, remember_password_key, this.remember_password);
    }

    public override void save_settings(KeyFile? key_file = null) {
        switch (this.service) {
            case Geary.Service.IMAP:
                key_file.set_value(Geary.Config.GROUP, Geary.Config.IMAP_HOST, this.host);
                key_file.set_integer(Geary.Config.GROUP, Geary.Config.IMAP_PORT, this.port);
                key_file.set_boolean(Geary.Config.GROUP, Geary.Config.IMAP_SSL, this.use_ssl);
                key_file.set_boolean(Geary.Config.GROUP, Geary.Config.IMAP_STARTTLS, this.use_starttls);
                break;
            case Geary.Service.SMTP:
                key_file.set_value(Geary.Config.GROUP, Geary.Config.SMTP_HOST, this.host);
                key_file.set_integer(Geary.Config.GROUP, Geary.Config.SMTP_PORT, this.port);
                key_file.set_boolean(Geary.Config.GROUP, Geary.Config.SMTP_SSL, this.use_ssl);
                key_file.set_boolean(Geary.Config.GROUP, Geary.Config.SMTP_STARTTLS, this.use_starttls);
                key_file.set_boolean(Geary.Config.GROUP, Geary.Config.SMTP_USE_IMAP_CREDENTIALS, this.smtp_use_imap_credentials);
                key_file.set_boolean(Geary.Config.GROUP, Geary.Config.SMTP_NOAUTH, this.smtp_noauth);
                break;
        }
    }

}
