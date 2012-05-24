/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
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
    
    public string host_specifier { get; private set; }
    public uint16 default_port { get; private set; }
    public Flags flags { get; private set; }
    public uint timeout_sec { get; private set; }
    
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

    public string to_string() {
        return "%s/default:%u".printf(host_specifier, default_port);
    }
}

