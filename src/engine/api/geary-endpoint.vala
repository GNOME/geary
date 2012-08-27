/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * An Endpoint represents the location of an Internet TCP connection as represented by a host,
 * a port, and flags and other parameters that specify the nature of the connection itself.
 */

public class Geary.Endpoint : Object {
    [Flags]
    public enum Flags {
        NONE = 0,
        SSL,
        STARTTLS,
        GRACEFUL_DISCONNECT;
        
        public inline bool is_all_set(Flags flags) {
            return (this & flags) == flags;
        }
        
        public inline bool is_any_set(Flags flags) {
            return (this & flags) != 0;
        }
    }
    
    public enum AttemptStarttls {
        YES,
        NO,
        HALT
    }
    
    public string host_specifier { get; private set; }
    public uint16 default_port { get; private set; }
    public Flags flags { get; private set; }
    public uint timeout_sec { get; private set; }
    
    public bool is_ssl { get {
        return flags.is_all_set(Flags.SSL);
    } }
    
    public bool use_starttls { get {
        return flags.is_all_set(Flags.STARTTLS);
    } }
    
    private SocketClient? socket_client = null;
    
    public Endpoint(string host_specifier, uint16 default_port, Flags flags, uint timeout_sec) {
        this.host_specifier = host_specifier;
        this.default_port = default_port;
        this.flags = flags;
        this.timeout_sec = timeout_sec;
    }
    
    public SocketClient get_socket_client() {
        if (socket_client != null)
            return socket_client;

        socket_client = new SocketClient();

        if (flags.is_all_set(Flags.SSL)) {
            socket_client.set_tls(true);
            socket_client.set_tls_validation_flags(TlsCertificateFlags.UNKNOWN_CA);
        }

        socket_client.set_timeout(timeout_sec);

        return socket_client;
    }

    public async SocketConnection connect_async(Cancellable? cancellable = null) throws Error {
        SocketConnection cx = yield get_socket_client().connect_to_host_async(host_specifier, default_port,
            cancellable);

        TcpConnection? tcp = cx as TcpConnection;
        if (tcp != null)
            tcp.set_graceful_disconnect(flags.is_all_set(Flags.GRACEFUL_DISCONNECT));

        return cx;
    }
    
    /**
     * Returns true if a STARTTLS command should be attempted on the connection:
     * (a) STARTTLS is reported available (a parameter specified by the caller to this method),
     * (b) not using SSL (so TLS is not required), and (c) STARTTLS is specified as a flag on
     * the Endpoint.
     *
     * If AttemptStarttls.HALT is returned, the caller should not proceed to pass any
     * authentication information down the connection; this situation indicates the connection is
     * insecure and the Endpoint is configured otherwise.
     */
    public AttemptStarttls attempt_starttls(bool starttls_available) {
        if (is_ssl || !use_starttls)
            return AttemptStarttls.NO;
        
        if (!starttls_available)
            return AttemptStarttls.HALT;
        
        return AttemptStarttls.YES;
    }
    
    public string to_string() {
        return "%s/default:%u".printf(host_specifier, default_port);
    }
}

