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


    public const string PROP_TRUST_UNTRUSTED_HOST = "trust-untrusted-host";


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

    /** Transport security certificate validation requirements. */
    public TlsCertificateFlags tls_validation_flags {
        get; set; default = TlsCertificateFlags.VALIDATE_ALL;
    }

    /**
     * The maximum number of commands that will be pipelined at once.
     *
     * If 0 (the default), there is no limit on the number of
     * pipelined commands sent to this endpoint.
     */
    public uint max_pipeline_batch_size = 0;

    /**
     * When set, TLS has reported certificate issues.
     *
     * @see trust_untrusted_host
     * @see untrusted_host
     */
    public TlsCertificateFlags tls_validation_warnings { get; private set; default = 0; }

    /**
     * The TLS certificate for an invalid or untrusted connection.
     */
    public TlsCertificate? untrusted_certificate { get; private set; default = null; }

    /**
     * When set, indicates the user has acceded to trusting the host even though TLS has reported
     * certificate issues.
     *
     * Initialized to {@link Trillian.UNKNOWN}, meaning the user must decide when warnings are
     * detected.
     *
     * @see untrusted_host
     * @see tls_validation_warnings
     */
    public Trillian trust_untrusted_host { get; set; default = Trillian.UNKNOWN; }

    /**
     * Returns true if (a) no TLS warnings have been detected or (b) user has explicitly acceded
     * to ignoring them and continuing the connection.
     *
     * This returns true if no connection has been attempted or connected and STARTTLS has not
     * been issued.  It's only when a connection is attempted can the certificate be examined
     * and this can accurately return false.  This behavior allows for a single code path to
     * first attempt a connection and thereafter only attempt connections when TLS issues have
     * been resolved by the user.
     *
     * @see tls_validation_warnings
     * @see trust_untrusted_host
     */
    public bool is_trusted_or_never_connected {
        get {
            return (tls_validation_warnings != 0)
                ? trust_untrusted_host.is_certain()
                : trust_untrusted_host.is_possible();
        }
    }

    private SocketClient? socket_client = null;

    /**
     * Fired when TLS certificate warnings are detected and the caller has not marked this
     * {@link Endpoint} as trusted via {@link trust_untrusted_host}.
     *
     * The connection will be closed when this is fired.  The caller should query the user about
     * how to deal with the situation.  If user wants to proceed, set {@link trust_untrusted_host}
     * to {@link Trillian.TRUE} and retry connection.
     *
     * @see tls_validation_warnings
     */
    public signal void untrusted_host(TlsNegotiationMethod method,
                                      GLib.TlsConnection cx);


    public Endpoint(GLib.SocketConnectable remote,
                    TlsNegotiationMethod method,
                    uint timeout_sec) {
        this.remote = remote;
        this.connectivity = new ConnectivityManager((NetworkAddress) this.remote);
        this.timeout_sec = timeout_sec;
        this.tls_method = method;
    }

    public async SocketConnection connect_async(Cancellable? cancellable = null) throws Error {
        return yield get_socket_client().connect_async(this.remote, cancellable);
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
            socket_client.set_tls_validation_flags(tls_validation_flags);
            socket_client.event.connect(on_socket_client_event);
        }

        socket_client.set_timeout(timeout_sec);

        return socket_client;
    }

    private void prepare_tls_cx(GLib.TlsClientConnection tls_cx) {
        tls_cx.server_identity = this.remote;
        tls_cx.validation_flags = this.tls_validation_flags;
        if (Endpoint.default_tls_database != null) {
            tls_cx.set_database(Endpoint.default_tls_database);
        }

        tls_cx.accept_certificate.connect(on_accept_certificate);
    }

    private bool report_tls_warnings(GLib.TlsConnection cx,
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

        // if user has marked this untrusted host as trusted already, accept warnings and move on
        if (trust_untrusted_host == Trillian.TRUE)
            return true;

        // signal an issue has been detected and return false to deny the connection
        untrusted_host(this.tls_method, cx);

        return false;
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
        return report_tls_warnings(cx, cert, flags);
    }

}
