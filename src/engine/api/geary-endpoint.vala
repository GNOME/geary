/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Encapsulates network configuration and state for remote service.
 */
public class Geary.Endpoint : BaseObject {


    /**
     * The default TLS certificate database to use when connecting.
     *
     * If not null, this will be set as the database on new TLS
     * connections.
     */
    public static GLib.TlsDatabase? default_tls_database = null;


    /** Returns {@link GLib.TlsCertificateFlags} as a string. */
    public static string tls_flag_to_string(GLib.TlsCertificateFlags flag) {
        // Vala to_string() for Flags enums currently doesn't work --
        // bummer...  Should only be called when a single flag is set,
        // otherwise returns a string indicating an unknown value
        switch (flag) {
            case TlsCertificateFlags.BAD_IDENTITY:
                return "BAD_IDENTITY";

            case TlsCertificateFlags.EXPIRED:
                return "EXPIRED";

            case TlsCertificateFlags.GENERIC_ERROR:
                return "GENERIC_ERROR";

            case TlsCertificateFlags.INSECURE:
                return "INSECURE";

            case TlsCertificateFlags.NOT_ACTIVATED:
                return "NOT_ACTIVATED";

            case TlsCertificateFlags.REVOKED:
                return "REVOKED";

            case TlsCertificateFlags.UNKNOWN_CA:
                return "UNKNOWN_CA";

            default:
                return "(unknown=%Xh)".printf(flag);
        }
    }


    /** Specifies how to connect to the remote endpoint. */
    public GLib.SocketConnectable remote { get; private set; }

    /** A connectivity manager for this endpoint. */
    public ConnectivityManager connectivity { get; private set; }

    /** Timeout for connection attempts, in seconds. */
    public uint timeout_sec { get; private set; }

    /** Transport security method to use when connecting. */
    public TlsNegotiationMethod tls_method { get; private set; }

    /**
     * When set, TLS has reported certificate issues.
     *
     * @see untrusted_host
     */
    public TlsCertificateFlags tls_validation_warnings { get; private set; default = 0; }

    /**
     * The TLS certificate for an invalid or untrusted connection.
     */
    public TlsCertificate? untrusted_certificate { get; private set; default = null; }

    private SocketClient? socket_client = null;


    /**
     * Emitted when unexpected TLS certificate warnings are detected.
     *
     * This occurs when a connection receives a TLS certificate
     * warning. The connection will be closed when this is fired. The
     * caller should query the user about how to deal with the
     * situation. If user wants to proceed, pin the certificate in a
     * way such that it accessible to the connection via {@link
     * default_tls_database}.
     *
     * @see AccountInformation.untrusted_host
     * @see tls_validation_warnings
     */
    public signal void untrusted_host(GLib.TlsConnection cx);


    public Endpoint(GLib.SocketConnectable remote,
                    TlsNegotiationMethod method,
                    uint timeout_sec) {
        this.remote = remote;
        this.connectivity = new ConnectivityManager((NetworkAddress) this.remote);
        this.timeout_sec = timeout_sec;
        this.tls_method = method;
    }

    public async GLib.SocketConnection connect_async(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        GLib.SocketClient client = get_socket_client();
        GLib.IOError? connect_error = null;
        try {
            return yield client.connect_async(this.remote, cancellable);
        } catch (GLib.IOError.NETWORK_UNREACHABLE err) {
            connect_error = err;
        }

        // Ubuntu 18.04 for some reason started throwing
        // NETWORK_UNREACHABLE when an AAAA record was resolved for
        // host name but no valid IPv6 network was available. Work
        // around by re-attempting manually resolving and selecting an
        // address to use. See issue #217.
        GLib.SocketAddressEnumerator addrs = this.remote.enumerate();
        GLib.SocketAddress? addr = yield addrs.next_async(cancellable);
        while (addr != null) {
            GLib.InetSocketAddress? inet_addr = addr as GLib.InetSocketAddress;
            if (inet_addr != null) {
                try {
                    return yield client.connect_async(
                        new GLib.InetSocketAddress(
                            inet_addr.address, (uint16) inet_addr.port
                        ),
                        cancellable
                    );
                } catch (GLib.IOError.NETWORK_UNREACHABLE err) {
                    // Keep going
                }
            }
            addr = yield addrs.next_async(cancellable);
        }

        throw connect_error;
    }

    public async TlsClientConnection starttls_handshake_async(IOStream base_stream,
        Cancellable? cancellable = null) throws Error {
        TlsClientConnection tls_cx = TlsClientConnection.new(
            base_stream, this.remote
        );
        prepare_tls_cx(tls_cx);

        yield tls_cx.handshake_async(Priority.DEFAULT, cancellable);

        return tls_cx;
    }

    public string to_string() {
        return this.remote.to_string();
    }

    private SocketClient get_socket_client() {
        if (socket_client != null)
            return socket_client;

        socket_client = new SocketClient();

        if (this.tls_method == TlsNegotiationMethod.TRANSPORT) {
            socket_client.set_tls(true);
            socket_client.event.connect(on_socket_client_event);
        }

        socket_client.set_timeout(timeout_sec);

        return socket_client;
    }

    private void prepare_tls_cx(GLib.TlsClientConnection tls_cx) {
        // Setting this on Ubuntu 18.04 breaks some TLS
        // connections. See issue #217.
        // tls_cx.server_identity = this.remote;
        if (Endpoint.default_tls_database != null) {
            tls_cx.set_database(Endpoint.default_tls_database);
        }

        tls_cx.accept_certificate.connect(on_accept_certificate);
    }

    private void report_tls_warnings(GLib.TlsConnection cx,
                                     GLib.TlsCertificate cert,
                                     GLib.TlsCertificateFlags warnings) {
        // TODO: Report or verify flags with user, but for now merely
        // log for informational/debugging reasons and accede
        message(
            "%s TLS warnings connecting to %s: %Xh (%s)",
            this.tls_method.to_string(), to_string(), warnings,
            tls_flags_to_string(warnings)
        );

        tls_validation_warnings = warnings;
        untrusted_certificate = cert;

        untrusted_host(cx);
    }

    private string tls_flags_to_string(TlsCertificateFlags flags) {
        StringBuilder builder = new StringBuilder();
        for (int pos = 0; pos < sizeof (TlsCertificateFlags) * 8; pos++) {
            TlsCertificateFlags flag = flags & (1 << pos);
            if (flag != 0) {
                if (!String.is_empty(builder.str))
                    builder.append(" | ");

                builder.append(tls_flag_to_string(flag));
            }
        }

        return !String.is_empty(builder.str) ? builder.str : "(none)";
    }

    private void on_socket_client_event(GLib.SocketClientEvent event,
                                        GLib.SocketConnectable? connectable,
                                        GLib.IOStream? ios) {
        // get TlsClientConnection to bind signals and set flags prior
        // to handshake
        if (event == SocketClientEvent.TLS_HANDSHAKING) {
            prepare_tls_cx((TlsClientConnection) ios);
        }
    }

    private bool on_accept_certificate(GLib.TlsConnection cx,
                                       GLib.TlsCertificate cert,
                                       GLib.TlsCertificateFlags flags) {
        // Per the docs for GTlsConnection.accept-certificate,
        // handling this signal must not block, so do this when idle
        GLib.Idle.add(() => {
                report_tls_warnings(cx, cert, flags);
                return GLib.Source.REMOVE;
            },
            GLib.Priority.HIGH
        );
        return false;
    }

}
