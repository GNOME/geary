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
        return ObjectUtils.from_enum_nick<Protocol>(
            typeof(Protocol), value.ascii_down()
        );
    }

    public string to_value() {
        return ObjectUtils.to_enum_nick<Protocol>(
            typeof(Protocol), this
        );
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


/**
 * Encapsulates configuration information for a network service.
 */
public class Geary.ServiceInformation : GLib.Object {


    /** Specifies the network protocol for this service. */
    public Protocol protocol { get; private set; }

    /** The server's address. */
    public string host { get; set; default = ""; }

    /** The server's port. */
    public uint16 port { get; set; default = 0; }

    /** The transport security method to use */
    public TlsNegotiationMethod transport_security { get; set; }

    /**
     * Determines the source of auth credentials for SMTP services.
     */
    public Credentials.Requirement credentials_requirement { get; set; }

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
     * Constructs a new configuration for a specific service.
     */
    public ServiceInformation(Protocol proto, ServiceProvider provider) {
        this.protocol = proto;
        // Prefer TLS by RFC 8314, but use START_TLS for SMTP for the
        // moment while its still more widely deployed.
        this.transport_security = (proto == Protocol.SMTP)
            ? TlsNegotiationMethod.START_TLS
            : TlsNegotiationMethod.TRANSPORT;
        this.credentials_requirement = (proto == Protocol.SMTP)
            ? Credentials.Requirement.USE_INCOMING
            : Credentials.Requirement.CUSTOM;

        provider.set_service_defaults(this);
    }

    /**
     * Constructs a copy of the given service configuration.
     */
    public ServiceInformation.copy(ServiceInformation other) {
        // Use OTHER here to get blank defaults
        this(other.protocol, ServiceProvider.OTHER);
        this.host = other.host;
        this.port = other.port;
        this.transport_security = other.transport_security;
        this.credentials = (
            other.credentials != null ? other.credentials.copy() : null
        );
        this.credentials_requirement = other.credentials_requirement;
        this.remember_password = other.remember_password;
    }


    /**
     * Returns the default port for this service type and settings.
     */
    public uint16 get_default_port() {
        uint16 port = 0;

        switch (this.protocol) {
        case IMAP:
            port = (this.transport_security == TlsNegotiationMethod.TRANSPORT)
                ? Imap.IMAP_TLS_PORT
                : Imap.IMAP_PORT;
            break;

        case SMTP:
            if (this.transport_security == TlsNegotiationMethod.TRANSPORT) {
                port = Smtp.SUBMISSION_TLS_PORT;
            } else if (this.credentials_requirement ==
                       Credentials.Requirement.NONE) {
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
             this.transport_security == other.transport_security &&
             ((this.credentials == null && other.credentials == null) ||
              (this.credentials != null && other.credentials != null &&
               this.credentials.equal_to(other.credentials))) &&
             this.credentials_requirement == other.credentials_requirement &&
             this.remember_password == other.remember_password)
        );
    }

}
