/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Endpoint : Object {
    [Flags]
    public enum Flags {
        NONE = 0,
        TLS
    }
    
    public string host_specifier { get; private set; }
    public uint16 default_port { get; private set; }
    public Flags flags { get; private set; }
    
    private SocketClient? socket_client = null;
    
    public Endpoint(string host_specifier, uint16 default_port, Flags flags) {
        this.host_specifier = host_specifier;
        this.default_port = default_port;
        this.flags = flags;
    }
    
    public SocketClient get_socket_client() {
        if (socket_client != null)
            return socket_client;
        
        socket_client = new SocketClient();
    
        if ((flags & Flags.TLS) != 0) {
            socket_client.set_tls(true);
            socket_client.set_tls_validation_flags(TlsCertificateFlags.UNKNOWN_CA);
        }
        
        return socket_client;
    }
    
    public async SocketConnection connect_async(Cancellable? cancellable = null) throws Error {
        return yield get_socket_client().connect_to_host_async(host_specifier, default_port,
            cancellable);
    }
    
    public string to_string() {
        return "%s/default:%u".printf(host_specifier, default_port);
    }
}

