/*
 * Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The network protocols supported by the engine for email services.
 */
public enum Geary.Protocol {
    IMAP,
    SMTP;


    public static Protocol for_value(string value)
        throws EngineError {
        switch (value.ascii_up()) {
        case "IMAP":
            return IMAP;
        case "SMTP":
            return SMTP;
        }
        throw new EngineError.BAD_PARAMETERS(
            "Unknown Protocol value: %s", value
        );
    }

    public string to_value() {
        string value = to_string();
        return value.substring(value.last_index_of("_") + 1);
    }

}

namespace Geary.Smtp {

    /** Default clear-text SMTP network port */
    public const uint16 SMTP_PORT = 25;

    /** Default clear-text SMTP submission network port */
    public const uint16 SUBMISSION_PORT = 587;

    /** Default transport-layer-encrypted SMTP submission network port */
    public const uint16 SUBMISSION_TLS_PORT = 465;

}


namespace Geary.Imap {

    /** Default clear-text IMAP network port */
    public const uint16 IMAP_PORT = 143;

    /** Default transport-layer-encrypted IMAP network port */
    public const uint16 IMAP_TLS_PORT = 993;

}


/** The method used to negotiate a TLS session, if any. */
public enum Geary.TlsNegotiationMethod {
    /** No TLS session should be established. */
    NONE,
    /** StartTLS should used to establish a session. */
    START_TLS,
    /** A TLS session should be established at the transport layer. */
    TRANSPORT;


    public static TlsNegotiationMethod for_value(string value)
        throws EngineError {
        return ObjectUtils.from_enum_nick<TlsNegotiationMethod>(
            typeof(TlsNegotiationMethod), value.ascii_down()
        );
    }

    public string to_value() {
        return ObjectUtils.to_enum_nick<TlsNegotiationMethod>(
            typeof(TlsNegotiationMethod), this
        );
    }

}


/** The credential source used to negotiate SMTP authentication, if any. */
public enum Geary.SmtpCredentials {
    /** No SMTP credentials are required. */
    NONE,
    /** The account's IMAP credentials should be used. */
    IMAP,
    /** Custom credentials are required for SMTP. */
    CUSTOM;

    public static SmtpCredentials for_value(string value)
        throws EngineError {
        return ObjectUtils.from_enum_nick<SmtpCredentials>(
            typeof(SmtpCredentials), value.ascii_down()
        );
    }

    public string to_value() {
        return ObjectUtils.to_enum_nick<SmtpCredentials>(
            typeof(SmtpCredentials), this
        );
    }

}


/**
 * Encapsulates configuration information for a network service.
 */
public class Geary.ServiceInformation : GLib.Object {


    /** Specifies if this service is for IMAP or SMTP. */
    public Protocol protocol { get; private set; }

    /** The server's address. */
    public string host { get; set; default = ""; }

    /** The server's port. */
    public uint16 port { get; set; default = 0; }

    /** The transport security method to use */
    public TlsNegotiationMethod transport_security {
        get {
            if (this.use_ssl) {
                return TlsNegotiationMethod.TRANSPORT;
            } else if (this.use_starttls) {
                return TlsNegotiationMethod.START_TLS;
            } else {
                return TlsNegotiationMethod.NONE;
            }
        }
        set {
            switch (value) {
            case TlsNegotiationMethod.NONE:
                this.use_starttls = false;
                this.use_ssl = false;
                break;
            case TlsNegotiationMethod.START_TLS:
                this.use_starttls = true;
                this.use_ssl = false;
                break;
            case TlsNegotiationMethod.TRANSPORT:
                this.use_starttls = false;
                this.use_ssl = true;
                break;
            }
        }
    }

    /** Whether STARTTLS is used when connecting to the server. */
    public bool use_starttls { get; set; default = false; }

    /** Whether SSL is used when connecting to the server. */
    public bool use_ssl { get; set; default = true; }

    /** The credentials used for authenticating. */
    public Credentials? credentials { get; set; default = null; }

    /**
     * Whether the password should be remembered.
     *
     * This only makes sense with providers that support saving the
     * password.
     */
    public bool remember_password { get; set; default = true; }

    /**
     * Determines the source of auth credentials for SMTP services.
     */
    public SmtpCredentials smtp_credentials_source {
        get {
            if (this.smtp_use_imap_credentials) {
                return SmtpCredentials.IMAP;
            } else if (this.smtp_noauth) {
                return SmtpCredentials.NONE;
            } else {
                return SmtpCredentials.CUSTOM;
            }
        }
        set {
            switch (value) {
            case SmtpCredentials.NONE:
                this.smtp_use_imap_credentials = false;
                this.smtp_noauth = true;
                break;
            case SmtpCredentials.IMAP:
                this.smtp_use_imap_credentials = true;
                this.smtp_noauth = false;
                break;
            case SmtpCredentials.CUSTOM:
                this.smtp_use_imap_credentials = false;
                this.smtp_noauth = false;
                break;
            }
        }
    }

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
    public bool smtp_use_imap_credentials { get; set; default = true; }


    /**
     * Constructs a new configuration for a specific service.
     */
    public ServiceInformation(Protocol proto) {
        this.protocol = proto;
    }

    /**
     * Constructs a copy of the given service configuration.
     */
    public ServiceInformation.copy(ServiceInformation other) {
        this(other.protocol);
        this.host = other.host;
        this.port = other.port;
        this.use_starttls = other.use_starttls;
        this.use_ssl = other.use_ssl;
        this.credentials = (
            other.credentials != null ? other.credentials.copy() : null
        );
        this.remember_password = other.remember_password;
        this.smtp_noauth = other.smtp_noauth;
        this.smtp_use_imap_credentials = other.smtp_use_imap_credentials;
    }


    /**
     * Returns the default port for this service type and settings.
     */
    public uint16 get_default_port() {
        uint16 port = 0;

        switch (this.protocol) {
        case IMAP:
            port = this.use_ssl
                ? Imap.IMAP_TLS_PORT
                : Imap.IMAP_PORT;
            break;

        case SMTP:
            if (this.use_ssl) {
                port = Smtp.SUBMISSION_TLS_PORT;
            } else if (this.smtp_noauth) {
                port = Smtp.SMTP_PORT;
            } else {
                port = Smtp.SUBMISSION_PORT;
            }
            break;
        }

        return port;
    }

    /**
     * Returns true if another object is equal to this one.
     */
    public bool equal_to(Geary.ServiceInformation other) {
        return (
            this == other ||
            (this.host == other.host &&
             this.port == other.port &&
             this.use_starttls == other.use_starttls &&
             this.use_ssl == other.use_ssl &&
             (this.credentials == null && other.credentials == null ||
              this.credentials != null && this.credentials.equal_to(other.credentials)) &&
             this.remember_password == other.remember_password &&
             this.smtp_noauth == other.smtp_noauth &&
             this.smtp_use_imap_credentials == other.smtp_use_imap_credentials)
        );
    }

}
