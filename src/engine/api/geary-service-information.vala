/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the different sources Geary might get its credentials from.
 */
public enum Geary.CredentialsProvider {
    LIBSECRET;

    public string to_string() {
        switch (this) {
            case LIBSECRET:
                return "libsecret";

            default:
                assert_not_reached();
        }
    }

    public static CredentialsProvider from_string(string str) throws Error {
        switch (str) {
            case "libsecret":
                return LIBSECRET;

            default:
                throw new KeyFileError.INVALID_VALUE(
                    "Unknown credentials provider type: %s", str
                );
        }
    }
}
/**
 * A type representing different methods for authenticating. For now we only
 * support password-based auth.
 */
public enum Geary.CredentialsMethod {
    PASSWORD;

    public string to_string() {
        switch (this) {
            case PASSWORD:
                return "password";

            default:
                assert_not_reached();
        }
    }

    public static CredentialsMethod from_string(string str) throws Error {
        switch (str) {
            case "password":
                return PASSWORD;

            default:
                throw new KeyFileError.INVALID_VALUE(
                    "Unknown credentials method type: %s", str
                );
        }
    }
}

/**
 * This class encloses all the information used when connecting with the server,
 * how to authenticate with it and which credentials to use. Derived classes
 * implement specific ways of doing that. For now, the only known implementation
 * resides in Geary.LocalServiceInformation.
 */
public abstract class Geary.ServiceInformation : GLib.Object {

    /** The server's address. */
    public string host { get; set; default = ""; }

    /** The server's port. */
    public uint16 port { get; set; }

    /** Whether STARTTLS is used when connecting to the server. */
    public bool use_starttls { get; set; default = false; }

    /** Whether SSL is used when connecting to the server. */
    public bool use_ssl { get; set; default = true; }

    /**
     * Whether the password should be remembered.
     *
     * This only makes sense with providers that support saving the password.
     */
    public bool remember_password { get; set; default = false; }

    /** The credentials used for authenticating. */
    public Geary.Credentials credentials { get; set; default = new Geary.Credentials(null, null); }

    /** Whether this class instance is used with the account's IMAP or the SMTP server. */
    public Geary.Service service { get; set; }

    /**
     * The credentials mediator used with the account.
     *
     * It is responsible for fetching and storing the credentials if applicable.
     */
    public Geary.CredentialsMediator? mediator { get; set; default = null; }

    /**
     * The default credentials provider.
     *
     * It is used for differentiating where Geary should get its credentials from,
     * in case there may be multiple sources.
     */
    public Geary.CredentialsProvider credentials_provider { get; set; default = CredentialsProvider.LIBSECRET; }

    /** The method used for authenticating with the server. */
    public Geary.CredentialsMethod credentials_method { get; set; default = CredentialsMethod.PASSWORD; }

    /**
     * Whether we should NOT authenticate with the server.
     *
     * Only valid if this instance represents an SMTP server.
     */
    public bool smtp_noauth { get; set; default = false; }

    /**
     * Specifies if we should use IMAP credentials.
     *
     * Only valid if this instance represents an SMTP server.
     */
    public bool smtp_use_imap_credentials { get; set; default = false; }

    /**
     * Loads the settings pertaining to this class's instance.
     *
     * This method depends on the concrete implementation used.
     */
    public abstract void load_settings(KeyFile? key_file = null) throws Error;

    /**
     * Loads the credentials pertaining to this class's instance.
     *
     * This method depends on the concrete implementation used.
     */
    public abstract void load_credentials(KeyFile? key_file = null, string? email_address = null) throws Error;

    /** Saves settings pertaining to this class's instance to a key file. */
    public abstract void save_settings(KeyFile? key_file = null);

    public void copy_from(Geary.ServiceInformation from) {
        this.host = from.host;
        this.port = from.port;
        this.use_starttls = from.use_starttls;
        this.use_ssl = from.use_ssl;
        this.remember_password = from.remember_password;
        this.credentials = from.credentials;
        this.service = from.service;
        this.mediator = from.mediator;
        this.credentials_provider = from.credentials_provider;
        this.credentials_method = from.credentials_method;
        this.smtp_noauth = from.smtp_noauth;
        this.smtp_use_imap_credentials = from.smtp_use_imap_credentials;
    }

    /**
     * Saves a new password for this instance's credentials, with the option
     * of remembering the password.
     */
    public void set_password(string password, bool remember = false) {
        this.credentials = new Credentials(this.credentials.user, password);
        this.remember_password = remember;
    }
}
