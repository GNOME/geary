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
    private DataInputStream? dins = null;
    private int ins_priority = Priority.DEFAULT;
    private Cancellable ins_cancellable = new Cancellable();
    private bool flow_controlled = true;
    private Deserializer des = new Deserializer();
    private uint8[] block_buffer = new uint8[4096];
    
    public virtual signal void connected() {
    }
    
    public virtual signal void disconnected() {
    }
    
    public virtual signal void flow_control(bool xon) {
    }
    
    public virtual signal void sent_command(Command cmd) {
    }
    
    public virtual signal void received_response(RootParameters params) {
    }
    
    public virtual signal void receive_failed(Error err) {
    }
    
    public ClientConnection(string host_specifier, uint16 default_port) {
        this.host_specifier = host_specifier;
        this.default_port = default_port;
        
        socket_client.set_tls(true);
        socket_client.set_tls_validation_flags(TlsCertificateFlags.UNKNOWN_CA);
        
        des.parameters_ready.connect(on_parameters_ready);
    }
    
    private void on_parameters_ready(RootParameters params) {
        received_response(params);
    }
    
    /*
    public void connect(Cancellable? cancellable = null) throws Error {
        if (cx != null)
            throw new IOError.EXISTS("Already connected to %s", to_string());
        
        cx = socket_client.connect_to_host(host_specifier, default_port, cancellable);
        iouts = new Imap.OutputStream(cx.output_stream);
        dins = new DataInputStream(cx.input_stream);
        dins.set_newline_type(DataStreamNewlineType.CR_LF);
        
        connected();
    }
    */
    
    public async void connect_async(Cancellable? cancellable = null) throws Error {
        if (cx != null)
            throw new IOError.EXISTS("Already connected to %s", to_string());
        
        cx = yield socket_client.connect_to_host_async(host_specifier, default_port, cancellable);
        dins = new DataInputStream(cx.input_stream);
        dins.set_newline_type(DataStreamNewlineType.CR_LF);
        
        connected();
    }
    
    /*
    public void disconnect(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            return;
        
        dins.close(cancellable);
        iouts.close(cancellable);
        cx.close(cancellable);
        
        dins = null;
        iouts = null;
        cx = null;
        
        disconnected();
    }
    */
    
    public async void disconnect_async(Cancellable? cancellable = null)
        throws Error {
        if (cx == null)
            return;
        
        yield cx.close_async(Priority.DEFAULT, cancellable);
        
        cx = null;
        dins = null;
        
        disconnected();
    }
    
    public void xon(int priority = Priority.DEFAULT) throws Error {
        check_for_connection();
        
        if (!flow_controlled)
            return;
        
        flow_controlled = false;
        ins_priority = priority;
        
        next_deserialize_step();
        
        flow_control(true);
    }
    
    private void next_deserialize_step() {
        switch (des.get_mode()) {
            case Deserializer.Mode.LINE:
                dins.read_line_async.begin(ins_priority, ins_cancellable, on_read_line);
            break;
            
            case Deserializer.Mode.BLOCK:
                long count = long.min(block_buffer.length, des.get_max_data_length());
                dins.read_async.begin(block_buffer[0:count], ins_priority, ins_cancellable,
                    on_read_block);
            break;
            
            default:
                error("Failed");
        }
    }
    
    private void on_read_line(Object? source, AsyncResult result) {
        try {
            string line = dins.read_line_async.end(result);
            des.push_line(line);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                receive_failed(err);
            
            return;
        }
        
        if (!flow_controlled)
            next_deserialize_step();
    }
    
    private void on_read_block(Object? source, AsyncResult result) {
        try {
            ssize_t read = dins.read_async.end(result);
            des.push_data(block_buffer[0:read]);
        } catch (Error err) {
            if (!(err is IOError.CANCELLED))
                receive_failed(err);
            
            return;
        }
        
        if (!flow_controlled)
            next_deserialize_step();
    }
    
    public void xoff() throws Error {
        check_for_connection();
        
        if (flow_controlled)
            return;
        
        // turn off the spigot
        // TODO: Don't cancel the read, merely don't post the next window
        flow_controlled = true;
        ins_cancellable.cancel();
        ins_cancellable = new Cancellable();
    }
    
    /*
    public void send(Command command, Cancellable? cancellable = null) throws Error {
        if (cx == null)
            throw new IOError.CLOSED("Not connected to %s", to_string());
        
        command.serialize(iouts, cancellable);
        
        sent_command(command);
    }
    */
    
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
        
        Serializer ser = new Serializer();
        cmd.serialize(ser);
        assert(ser.has_content());
        
        yield write_all_async(ser, priority, cancellable);
        
        sent_command(cmd);
    }
    
    public async void send_multiple_async(Gee.List<Command> cmds, int priority = Priority.DEFAULT,
        Cancellable? cancellable = null) throws Error {
        if (cmds.size == 0)
            return;
        
        check_for_connection();
        
        Serializer ser = new Serializer();
        foreach (Command cmd in cmds)
            cmd.serialize(ser);
        assert(ser.has_content());
        
        yield write_all_async(ser, priority, cancellable);
        
        // Variable named due to this bug: https://bugzilla.gnome.org/show_bug.cgi?id=596861
        foreach (Command cmd2 in cmds)
            sent_command(cmd2);
    }
    
    // Can't pass the raw buffer due to this bug: https://bugzilla.gnome.org/show_bug.cgi?id=639054
    private async void write_all_async(Serializer ser, int priority, Cancellable? cancellable)
        throws Error {
        ssize_t index = 0;
        size_t length = ser.get_content_length();
        while (index < length) {
            index += yield cx.output_stream.write_async(ser.get_content()[index:length],
                priority, cancellable);
            if (index < length)
                debug("PARTIAL WRITE TO %s: %lu/%lu bytes", to_string(), index, length);
        }
    }
    
    private void check_for_connection() throws Error {
        if (cx == null)
            throw new IOError.CLOSED("Not connected to %s", to_string());
    }
    
    public string to_string() {
        return "%s:%ud".printf(host_specifier, default_port);
    }
}

