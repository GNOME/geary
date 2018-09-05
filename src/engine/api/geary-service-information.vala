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


/** The credentials used to negotiate SMTP authentication, if any. */
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
 * This class encloses all the information used when connecting with the server,
 * how to authenticate with it and which credentials to use. Derived classes
 * implement specific ways of doing that. For now, the only known implementation
 * resides in Geary.LocalServiceInformation.
 */
public abstract class Geary.ServiceInformation : GLib.Object {


    /** Specifies if this service is for IMAP or SMTP. */
    public Protocol protocol { get; private set; }

    /** The server's address. */
    public string host { get; set; default = ""; }

    /** The server's port. */
    public uint16 port { get; set; }

    /** Whether STARTTLS is used when connecting to the server. */
    public bool use_starttls { get; set; default = false; }

    /** Whether SSL is used when connecting to the server. */
    public bool use_ssl { get; set; default = true; }

    /** The credentials used for authenticating. */
    public Credentials? credentials { get; set; default = null; }

    /**
     * The credentials mediator used with this service.
     *
     * It is responsible for fetching and storing the credentials if
     * applicable.
     */
    public CredentialsMediator mediator { get; private set; }

    /**
     * Whether the password should be remembered.
     *
     * This only makes sense with providers that support saving the
     * password.
     */
    public bool remember_password { get; set; default = true; }

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
     * The network endpoint for this service.
     *
     * This will be null until the service's account has been added to
     * the engine, and after it has been removed from the engine.
     */
    public Endpoint? endpoint { get; internal set; }


    protected ServiceInformation(Protocol proto, CredentialsMediator mediator) {
        this.protocol = proto;
        this.mediator = mediator;
    }


    public abstract ServiceInformation temp_copy();

    public void copy_from(Geary.ServiceInformation from) {
        this.host = from.host;
        this.port = from.port;
        this.use_starttls = from.use_starttls;
        this.use_ssl = from.use_ssl;
        this.credentials = (
            from.credentials != null ? from.credentials.copy() : null
        );
        this.mediator = from.mediator;
        this.remember_password = from.remember_password;
        this.smtp_noauth = from.smtp_noauth;
        this.smtp_use_imap_credentials = from.smtp_use_imap_credentials;
    }

}
