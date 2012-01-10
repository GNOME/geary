/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientConnection {
    public const uint16 DEFAULT_PORT = 143;
    public const uint16 DEFAULT_PORT_TLS = 993;
    
    private const int FLUSH_TIMEOUT_MSEC = 100;
    
    // Used solely for debugging
    private static int next_cx_id = 0;
    
    private Geary.Endpoint endpoint;
    private int cx_id;
    private SocketConnection? cx = null;
    private Serializer? ser = null;
    private Deserializer? des = null;
    private Geary.NonblockingMutex send_mutex = new Geary.NonblockingMutex();
    private int tag_counter = 0;
    private char tag_prefix = 'a';
    private uint flush_timeout_id = 0;
    
    public virtual signal void connected() {
        Logging.debug(Logging.Flag.NETWORK, "[%s] connected to %s", to_string(),
            endpoint.to_string());
    }
    
    public virtual signal void disconnected() {
        Logging.debug(Logging.Flag.NETWORK, "[%s] disconnected from %s", to_string(),
            endpoint.to_string());
    }
    
    public virtual signal void sent_command(Command cmd) {
        Logging.debug(Logging.Flag.NETWORK, "[%s S] %s", to_string(), cmd.to_string());
    }
    
    public virtual signal void flush_failure(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] flush failure: %s", to_string(), err.message);
    }
    
    public virtual signal void received_status_response(StatusResponse status_response) {
        Logging.debug(Logging.Flag.NETWORK, "[%s R] %s", to_string(), status_response.to_string());
    }
    
    public virtual signal void received_server_data(ServerData server_data) {
        Logging.debug(Logging.Flag.NETWORK, "[%s R] %s", to_string(), server_data.to_string());
    }
    
    public virtual signal void received_bad_response(RootParameters root, ImapError err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] recv bad response %s: %s", to_string(),
            root.to_string(), err.message);
    }
    
    public virtual signal void recv_closed() {
        Logging.debug(Logging.Flag.NETWORK, "[%s] recv closed", to_string());
    }
    
    public virtual signal void receive_failure(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] recv failure: %s", to_string(), err.message);
    }
    
    public virtual signal void deserialize_failure(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] deserialize failure: %s", to_string(),
            err.message);
    }
    
    public ClientConnection(Geary.Endpoint endpoint) {
        this.endpoint = endpoint;
        cx_id = next_cx_id++;
    }
    
    ~ClientConnection() {
        // TODO: Close connection as gracefully as possible
        if (flush_timeout_id != 0)
            Source.remove(flush_timeout_id);
    }
    
    /**
     * Generates a unique tag for the IMAP connection in the form of "<a-z><000-999>".
     */
    private Tag generate_tag() {
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
        
        cx = yield endpoint.connect_async(cancellable);
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
        
        des.xoff();
        
        try {
            yield cx.close_async(Priority.DEFAULT, cancellable);
        } finally {
            cx = null;
            ser = null;
            des = null;
            
            disconnected();
        }
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
        deserialize_failure(new ImapError.PARSE_ERROR("Unable to deserialize from %s", to_string()));
    }
    
    private void on_eos() {
        recv_closed();
    }
    
    public async void send_async(Command cmd, Cancellable? cancellable = null) throws Error {
        check_for_connection();
        
        // need to run this in critical section because OutputStreams can only be written to
        // serially
        int token = yield send_mutex.claim_async(cancellable);
        
        // Always assign a new tag; Commands with pre-assigned Tags should not be re-sent.
        // (Do this inside the critical section to ensure commands go out in Tag order; this is not
        // an IMAP requirement but makes tracing commands easier.)
        cmd.assign_tag(generate_tag());
        
        yield cmd.serialize(ser);
        
        send_mutex.release(ref token);
        
        if (flush_timeout_id == 0)
            flush_timeout_id = Timeout.add(FLUSH_TIMEOUT_MSEC, on_flush_timeout);
        
        sent_command(cmd);
    }
    
    private bool on_flush_timeout() {
        do_flush_async.begin();
        
        flush_timeout_id = 0;
        
        return false;
    }
    
    private async void do_flush_async() {
        try {
            if (ser != null)
                yield ser.flush_async();
        } catch (Error err) {
            flush_failure(err);
        }
    }
    
    private void check_for_connection() throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", to_string());
    }
    
    public string to_string() {
        if (cx != null) {
            try {
                return "%04X/%s".printf(cx_id,
                    Inet.address_to_string((InetSocketAddress) cx.get_remote_address()));
            } catch (Error err) {
                // fall through
            }
        }
        
        return "%04X/%s".printf(cx_id, endpoint.to_string());
    }
}

