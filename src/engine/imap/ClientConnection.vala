/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientConnection {
    public const uint16 DEFAULT_PORT = 143;
    public const uint16 DEFAULT_PORT_TLS = 993;
    
    private string host_specifier;
    private uint16 default_port;
    private SocketClient socket_client = new SocketClient();
    private SocketConnection? cx = null;
    private Serializer? ser = null;
    private Deserializer? des = null;
    private int tag_counter = 0;
    private char tag_prefix = 'a';
    
    public virtual signal void connected() {
    }
    
    public virtual signal void disconnected() {
    }
    
    public virtual signal void sent_command(Command cmd) {
    }
    
    public virtual signal void received_status_response(StatusResponse status_response) {
    }
    
    public virtual signal void received_server_data(ServerData server_data) {
    }
    
    public virtual signal void received_bad_response(RootParameters root, ImapError err) {
    }
    
    public virtual signal void recv_closed() {
    }
    
    public virtual signal void receive_failure(Error err) {
    }
    
    public virtual signal void deserialize_failure() {
    }
    
    public ClientConnection(string host_specifier, uint16 default_port) {
        this.host_specifier = host_specifier;
        this.default_port = default_port;
        
        socket_client.set_tls(true);
        socket_client.set_tls_validation_flags(TlsCertificateFlags.UNKNOWN_CA);
    }
    
    ~ClientConnection() {
        // TODO: Close connection as gracefully as possible
    }
    
    /**
     * Generates a unique tag for the IMAP connection in the form of "<a-z><000-999>".
     */
    public Tag generate_tag() {
        // watch for odometer rollover
        if (++tag_counter >= 1000) {
            tag_counter = 0;
            if (tag_prefix == 'z')
                tag_prefix = 'a';
            else
                tag_prefix++;
        }
        
        // TODO This could be optimized, but we'll leave it for now.
        return new Tag("%c%03d".printf(tag_prefix, tag_counter));
    }
    
    /**
     * Returns silently if a connection is already established.
     */
    public async void connect_async(Cancellable? cancellable = null) throws Error {
        if (cx != null) {
            debug("Already connected to %s", to_string());
            
            return;
        }
        
        cx = yield socket_client.connect_to_host_async(host_specifier, default_port, cancellable);
        ser = new Serializer(new BufferedOutputStream(cx.output_stream));
        des = new Deserializer(new BufferedInputStream(cx.input_stream));
        des.parameters_ready.connect(on_parameters_ready);
        des.receive_failure.connect(on_receive_failure);
        des.deserialize_failure.connect(on_deserialize_failure);
        des.eos.connect(on_eos);
        
        connected();
        
        des.xon();
    }
    
    public async void disconnect_async(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            return;
        
        yield cx.close_async(Priority.DEFAULT, cancellable);
        
        cx = null;
        ser = null;
        des = null;
        
        disconnected();
    }
    
    private void on_parameters_ready(RootParameters root) {
        try {
            bool is_status_response;
            ServerResponse response = ServerResponse.from_server(root, out is_status_response);
            
            if (is_status_response)
                received_status_response((StatusResponse) response);
            else
                received_server_data((ServerData) response);
        } catch (ImapError err) {
            received_bad_response(root, err);
        }
    }
    
    private void on_receive_failure(Error err) {
        receive_failure(err);
    }
    
    private void on_deserialize_failure() {
        deserialize_failure();
    }
    
    private void on_eos() {
        recv_closed();
    }
    
    /**
     * Convenience method for send_async.begin().
     */
    public void post(Command cmd, AsyncReadyCallback cb, int priority = Priority.DEFAULT,
        Cancellable? cancellable = null) {
        send_async.begin(cmd, priority, cancellable, cb);
    }
    
    /**
     * Convenience method for sync_async.end().  This is largely provided for symmetry with
     * post_send().
     */
    public void finish_post(AsyncResult result) throws Error {
        send_async.end(result);
    }
    
    public async void send_async(Command cmd, int priority = Priority.DEFAULT, 
        Cancellable? cancellable = null) throws Error {
        check_for_connection();
        
        cmd.serialize(ser);
        
        // TODO: At this point, we flush each command as it's written; at some point we'll have
        // a queuing strategy that means serialized data is pushed out to the wire only at certain
        // times
        yield ser.flush_async(priority, cancellable);
        
        sent_command(cmd);
    }
    
    private void check_for_connection() throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", to_string());
    }
    
    public string to_string() {
        return "%s:%ud".printf(host_specifier, default_port);
    }
}

