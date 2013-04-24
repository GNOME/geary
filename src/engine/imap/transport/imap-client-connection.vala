/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientConnection : BaseObject {
    public const uint16 DEFAULT_PORT = 143;
    public const uint16 DEFAULT_PORT_SSL = 993;
    
    /**
     * This is set very high to allow for IDLE connections to remain connected even when
     * there is no traffic on them.  The side-effect is that if the physical connection is dropped,
     * no error is reported and the connection won't know about it until the next send operation.
     *
     * RECOMMENDED_TIMEOUT_SEC is more realistic in that if a connection is hung it's important
     * to detect it early and drop it, at the expense of more keepalive traffic.
     *
     * In general, whatever timeout is used for the ClientConnection must be slightly higher than
     * the keepalive timeout used by ClientSession, otherwise the ClientConnection will be dropped
     * before the keepalive is sent.
     */
    public const uint DEFAULT_TIMEOUT_SEC = ClientSession.MIN_KEEPALIVE_SEC + 15;
    public const uint RECOMMENDED_TIMEOUT_SEC = ClientSession.RECOMMENDED_KEEPALIVE_SEC + 15;
    
    /**
     * The default timeout for an issued command to result in a response code from the server.
     * A timed-out command will result in the connection being forcibly closed.
     */
    public const uint DEFAULT_COMMAND_TIMEOUT_SEC = 15;
    
    private const int FLUSH_TIMEOUT_MSEC = 100;
    
    private enum State {
        UNCONNECTED,
        CONNECTED,
        IDLING,
        IDLE,
        DEIDLING,
        DISCONNECTED,
        
        COUNT
    }
    
    private static string state_to_string(uint state) {
        return ((State) state).to_string();
    }
    
    private enum Event {
        CONNECTED,
        DISCONNECTED,
        
        // Use issue_conditional_event() for SEND events, using the result to determine whether
        // or not to continue; the transition handlers do no signalling or I/O
        SEND,
        SEND_IDLE,
        
        // RECVD_* will emit appropriate signals inside their transition handlers; do *not* use
        // issue_conditional_event() for these events
        RECVD_STATUS_RESPONSE,
        RECVD_SERVER_DATA,
        RECVD_CONTINUATION_RESPONSE,
        
        COUNT
    }
    
    private static string event_to_string(uint event) {
        return ((Event) event).to_string();
    }
    
    private static Geary.State.MachineDescriptor machine_desc = new Geary.State.MachineDescriptor(
        "Geary.Imap.ClientConnection", State.UNCONNECTED, State.COUNT, Event.COUNT,
        state_to_string, event_to_string);
    
    // Used solely for debugging
    private static int next_cx_id = 0;
    
    public uint command_timeout_sec { get; set; default = DEFAULT_COMMAND_TIMEOUT_SEC; }
    
    private Geary.Endpoint endpoint;
    private int cx_id;
    private Geary.State.Machine fsm;
    private SocketConnection? cx = null;
    private IOStream? ios = null;
    private Serializer? ser = null;
    private Deserializer? des = null;
    private Geary.NonblockingMutex send_mutex = new Geary.NonblockingMutex();
    private int tag_counter = 0;
    private char tag_prefix = 'a';
    private uint flush_timeout_id = 0;
    private bool idle_when_quiet = false;
    private Gee.HashSet<Tag> posted_idle_tags = new Gee.HashSet<Tag>();
    private uint timeout_id = 0;
    private uint timeout_cmd_count = 0;
    
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
    
    public virtual signal void in_idle(bool idling) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] in idle: %s", to_string(), idling.to_string());
    }
    
    public virtual signal void received_status_response(StatusResponse status_response) {
        Logging.debug(Logging.Flag.NETWORK, "[%s R] %s", to_string(), status_response.to_string());
    }
    
    public virtual signal void received_server_data(ServerData server_data) {
        Logging.debug(Logging.Flag.NETWORK, "[%s R] %s", to_string(), server_data.to_string());
    }
    
    public virtual signal void received_continuation_response(ContinuationResponse continuation_response) {
        Logging.debug(Logging.Flag.NETWORK, "[%s R] %s", to_string(), continuation_response.to_string());
    }
    
    public virtual signal void received_bytes(size_t bytes) {
        // this generates a *lot* of debug logging if one was placed here, so it's not
    }
    
    public virtual signal void received_bad_response(RootParameters root, ImapError err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] recv bad response %s: %s", to_string(),
            root.to_string(), err.message);
    }
    
    public virtual signal void recv_closed() {
        Logging.debug(Logging.Flag.NETWORK, "[%s] recv closed", to_string());
    }
    
    public virtual signal void send_failure(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] send failure: %s", to_string(), err.message);
    }
    
    public virtual signal void receive_failure(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] recv failure: %s", to_string(), err.message);
    }
    
    public virtual signal void deserialize_failure(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] deserialize failure: %s", to_string(),
            err.message);
    }
    
    public virtual signal void close_error(Error err) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] close error: %s", to_string(), err.message);
    }
    
    public ClientConnection(Geary.Endpoint endpoint) {
        this.endpoint = endpoint;
        cx_id = next_cx_id++;
        
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.UNCONNECTED, Event.CONNECTED, on_connected),
            new Geary.State.Mapping(State.UNCONNECTED, Event.DISCONNECTED, Geary.State.nop),
            
            new Geary.State.Mapping(State.CONNECTED, Event.SEND, on_proceed),
            new Geary.State.Mapping(State.CONNECTED, Event.SEND_IDLE, on_send_idle),
            new Geary.State.Mapping(State.CONNECTED, Event.RECVD_STATUS_RESPONSE, on_status_response),
            new Geary.State.Mapping(State.CONNECTED, Event.RECVD_SERVER_DATA, on_server_data),
            new Geary.State.Mapping(State.CONNECTED, Event.RECVD_CONTINUATION_RESPONSE, on_continuation),
            new Geary.State.Mapping(State.CONNECTED, Event.DISCONNECTED, on_disconnected),
            
            new Geary.State.Mapping(State.IDLING, Event.SEND, on_idle_send),
            new Geary.State.Mapping(State.IDLING, Event.SEND_IDLE, on_no_proceed),
            new Geary.State.Mapping(State.IDLING, Event.RECVD_STATUS_RESPONSE, on_idle_status_response),
            new Geary.State.Mapping(State.IDLING, Event.RECVD_SERVER_DATA, on_server_data),
            new Geary.State.Mapping(State.IDLING, Event.RECVD_CONTINUATION_RESPONSE, on_idling_continuation),
            new Geary.State.Mapping(State.IDLING, Event.DISCONNECTED, on_disconnected),
            
            new Geary.State.Mapping(State.IDLE, Event.SEND, on_idle_send),
            new Geary.State.Mapping(State.IDLE, Event.SEND_IDLE, on_no_proceed),
            new Geary.State.Mapping(State.IDLE, Event.RECVD_STATUS_RESPONSE, on_idle_status_response),
            new Geary.State.Mapping(State.IDLE, Event.RECVD_SERVER_DATA, on_server_data),
            new Geary.State.Mapping(State.IDLE, Event.RECVD_CONTINUATION_RESPONSE, on_idle_continuation),
            new Geary.State.Mapping(State.IDLE, Event.DISCONNECTED, on_disconnected),
            
            new Geary.State.Mapping(State.DEIDLING, Event.SEND, on_proceed),
            new Geary.State.Mapping(State.DEIDLING, Event.SEND_IDLE, on_send_idle),
            new Geary.State.Mapping(State.DEIDLING, Event.RECVD_STATUS_RESPONSE, on_idle_status_response),
            new Geary.State.Mapping(State.DEIDLING, Event.RECVD_SERVER_DATA, on_server_data),
            new Geary.State.Mapping(State.DEIDLING, Event.RECVD_CONTINUATION_RESPONSE, on_idling_continuation),
            new Geary.State.Mapping(State.DEIDLING, Event.DISCONNECTED, on_disconnected),
            
            // TODO: A DISCONNECTING state would be helpful here, allowing for responses and data
            // received from the server after a send error caused a disconnect to be signalled to
            // subscribers before moving to the DISCONNECTED state.  That would require more work,
            // allowing for the caller (ClientSession) to close the receive channel and wait for
            // everything to flush out before it shifted to a DISCONNECTED state as well.
            new Geary.State.Mapping(State.DISCONNECTED, Event.SEND, on_no_proceed),
            new Geary.State.Mapping(State.DISCONNECTED, Event.SEND_IDLE, on_no_proceed),
            new Geary.State.Mapping(State.DISCONNECTED, Event.RECVD_STATUS_RESPONSE, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTED, Event.RECVD_SERVER_DATA, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTED, Event.RECVD_CONTINUATION_RESPONSE, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTED, Event.DISCONNECTED, Geary.State.nop)
        };
        
        fsm = new Geary.State.Machine(machine_desc, mappings, on_bad_transition);
        fsm.set_logging(false);
    }
    
    /**
     * Generates a unique tag for the IMAP connection in the form of "<a-z><000-999>".
     */
    private Tag generate_tag() {
        // watch for odometer rollover
        if (++tag_counter >= 1000) {
            tag_counter = 0;
            tag_prefix = (tag_prefix != 'z') ? tag_prefix + 1 : 'a';
        }
        
        // TODO This could be optimized, but we'll leave it for now.
        return new Tag("%c%03d".printf(tag_prefix, tag_counter));
    }
    
    /**
     * If true, when the connection is not sending commands ("quiet"), it will issue an IDLE command
     * to enter a state where unsolicited server data may be sent from the server without resorting
     * to NOOP keepalives.  (Note that keepalives are still required to hold the connection open,
     * according to the IMAP specification.)
     *
     * Note that this will *not* break a connection out of IDLE state alone; a command needs to be
     * flushed down the pipe to do that.  (NOOP would be a good choice.)  Nor will this initiate
     * an IDLE command either; it can only do that after sending a command (again, NOOP would be
     * a good choice).
     */
    public void set_idle_when_quiet(bool idle_when_quiet) {
        this.idle_when_quiet = idle_when_quiet;
    }
    
    public bool get_idle_when_quiet() {
        return idle_when_quiet;
    }
    
    public SocketAddress? get_remote_address() {
        if (cx == null)
            return null;
        
        try {
            return cx.get_remote_address();
        } catch (Error err) {
            debug("Unable to retrieve remote address: %s", err.message);
        }
        
        return null;
    }
    
    public SocketAddress? get_local_address() {
        if (cx == null)
            return null;
        
        try {
            return cx.get_local_address();
        } catch (Error err) {
            debug("Unable to retrieve remote address: %s", err.message);
        }
        
        return null;
    }
    
    /**
     * Returns true if the connection is in an IDLE state.  The or_idling parameter means to return
     * true if the connection is working toward an IDLE state (but additional responses are being
     * returned from the server before getting there).
     */
    public bool is_in_idle(bool or_idling) {
        switch (fsm.get_state()) {
            case State.IDLE:
                return true;
            
            case State.IDLING:
                return or_idling;
            
            default:
                return false;
        }
    }
    
    public bool install_send_converter(Converter converter) {
        return ser.install_converter(converter);
    }
    
    public bool install_recv_converter(Converter converter) {
        return des.install_converter(converter);
    }
    
    /**
     * Returns silently if a connection is already established.
     */
    public async void connect_async(Cancellable? cancellable = null) throws Error {
        if (cx != null) {
            debug("Already connected/connecting to %s", to_string());
            
            return;
        }
        
        cx = yield endpoint.connect_async(cancellable);
        ios = cx;
        
        // issue CONNECTED event and fire signal because the moment the channels are hooked up,
        // data can start flowing
        fsm.issue(Event.CONNECTED);
        
        connected();
        
        try {
            yield open_channels_async();
        } catch (Error err) {
            // if this fails, need to close connection because the caller will not call
            // disconnect_async()
            try {
                yield cx.close_async();
            } catch (Error close_err) {
                // ignored
            }
            
            fsm.issue(Event.DISCONNECTED);
            
            cx = null;
            ios = null;
            
            throw err;
        }
    }
    
    public async void disconnect_async(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            return;
        
        // To guard against reentrancy
        SocketConnection close_cx = cx;
        cx = null;
        ios = null;
        
        // unschedule before yielding to stop the Deserializer
        unschedule_flush_timeout();
        
        // cancel all outstanding commmand timeouts
        cancel_timeout();
        
        // close the Serializer and Deserializer
        yield close_channels_async(cancellable);
        
        // close the actual streams and the connection itself
        Error? close_err = null;
        try {
            debug("[%s] Disconnecting...", to_string());
            yield close_cx.close_async(Priority.DEFAULT, cancellable);
            debug("[%s] Disconnected", to_string());
        } catch (Error err) {
            debug("[%s] Error disconnecting: %s", to_string(), err.message);
            close_err = err;
        } finally {
            fsm.issue(Event.DISCONNECTED);
            
            if (close_err != null)
                close_error(close_err);
            
            disconnected();
        }
    }
    
    private async void open_channels_async() throws Error {
        assert(ios != null);
        assert(ser == null);
        assert(des == null);
        
        // not buffering the Serializer because it buffers using a MemoryOutputStream and not
        // buffering the Deserializer because it uses a DataInputStream, which is buffered
        ser = new Serializer(ios.output_stream);
        des = new Deserializer(ios.input_stream);
        
        des.parameters_ready.connect(on_parameters_ready);
        des.bytes_received.connect(on_bytes_received);
        des.receive_failure.connect(on_receive_failure);
        des.deserialize_failure.connect(on_deserialize_failure);
        des.eos.connect(on_eos);
        
        yield des.start_async();
    }
    
    // Closes the Serializer and Deserializer, but does NOT close the underlying streams
    private async void close_channels_async(Cancellable? cancellable) throws Error {
        // disconnect from Deserializer before yielding to stop it
        if (des != null) {
            des.parameters_ready.disconnect(on_parameters_ready);
            des.bytes_received.disconnect(on_bytes_received);
            des.receive_failure.disconnect(on_receive_failure);
            des.deserialize_failure.disconnect(on_deserialize_failure);
            des.eos.disconnect(on_eos);
            
            yield des.stop_async();
        }
        
        // TODO: May need to commit Serializer before disconnecting
        ser = null;
        des = null;
    }
    
    public async void starttls_async(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            throw new ImapError.NOT_SUPPORTED("[%s] Unable to enable TLS: no connection", to_string());
        
        // (mostly) silent fail in this case
        if (cx is TlsClientConnection) {
            debug("[%s] Already TLS connection", to_string());
            
            return;
        }
        
        // Close the Serializer/Deserializer, as need to use the TLS streams
        yield close_channels_async(cancellable);
        
        // wrap connection with TLS connection
        TlsClientConnection tls_cx = yield endpoint.starttls_handshake_async(cx,
            cx.get_remote_address(), cancellable);
        
        ios = tls_cx;
        
        // re-open Serializer/Deserializer with the new streams
        yield open_channels_async();
    }
    
    private void on_parameters_ready(RootParameters root) {
        try {
            ServerResponse.Type response_type;
            ServerResponse response = ServerResponse.migrate_from_server(root, out response_type);
            
            switch (response_type) {
                case ServerResponse.Type.STATUS_RESPONSE:
                    fsm.issue(Event.RECVD_STATUS_RESPONSE, null, response);
                break;
                
                case ServerResponse.Type.SERVER_DATA:
                    fsm.issue(Event.RECVD_SERVER_DATA, null, response);
                break;
                
                case ServerResponse.Type.CONTINUATION_RESPONSE:
                    fsm.issue(Event.RECVD_CONTINUATION_RESPONSE, null, response);
                break;
                
                default:
                    assert_not_reached();
            }
        } catch (ImapError err) {
            received_bad_response(root, err);
        }
    }
    
    private void on_bytes_received(size_t bytes) {
        // as long as receiving someone on the connection, keep the outstanding command timeouts
        // alive ... this primarily prevents against the case where a command that generates a long
        // download doesn't timeout the commands behind it
        increase_timeout();
        
        received_bytes(bytes);
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
    
    // TODO: Guard against reentrancy
    public async void send_async(Command cmd, Cancellable? cancellable = null) throws Error {
        check_for_connection();
        
        if (!issue_conditional_event(Event.SEND)) {
            debug("[%s] Send async not allowed", to_string());
            
            throw new ImapError.NOT_CONNECTED("Send not allowed: connection in %s state",
                fsm.get_state_string(fsm.get_state()));
        }
        
        // need to run this in critical section because OutputStreams can only be written to
        // serially
        int token = yield send_mutex.claim_async(cancellable);
        
        // Always assign a new tag; Commands with pre-assigned Tags should not be re-sent.
        // (Do this inside the critical section to ensure commands go out in Tag order; this is not
        // an IMAP requirement but makes tracing commands easier.)
        cmd.assign_tag(generate_tag());
        
        // set the timeout on this command; note that a zero-second timeout means no timeout,
        // and that there's no timeout on serialization
        cmd_started_timeout();
        
        Error? ser_err = null;
        try {
            // watch for disconnect while waiting for mutex
            if (ser != null) {
                // TODO: Make serialize non-blocking; this would also remove the need for a send_mutex
                // (although reentrancy should still be checked for)
                yield cmd.serialize(ser);
            } else {
                ser_err = new ImapError.NOT_CONNECTED("Send not allowed: connection in %s state",
                    fsm.get_state_string(fsm.get_state()));
            }
        } catch (Error err) {
            debug("[%s] Error serializing command: %s", to_string(), err.message);
            ser_err = err;
        }
        
        send_mutex.release(ref token);
        
        if (ser_err != null) {
            send_failure(ser_err);
            
            throw ser_err;
        }
        
        // Reset flush timer so it only fires after n msec after last command pushed out to stream
        reschedule_flush_timeout();
        
        // TODO: technically lying a little bit here; since ClientSession keepalives are rescheduled
        // by this signal, will want to tighten this up a bit in the future
        sent_command(cmd);
    }
    
    private void reschedule_flush_timeout() {
        unschedule_flush_timeout();
        
        if (flush_timeout_id == 0)
            flush_timeout_id = Timeout.add_full(Priority.LOW, FLUSH_TIMEOUT_MSEC, on_flush_timeout);
    }
    
    private void unschedule_flush_timeout() {
        if (flush_timeout_id != 0) {
            Source.remove(flush_timeout_id);
            flush_timeout_id = 0;
        }
    }
    
    private bool on_flush_timeout() {
        do_flush_async.begin();
        
        flush_timeout_id = 0;
        
        return false;
    }
    
    private async void do_flush_async() {
        // need to signal when the IDLE command is sent, for completeness
        IdleCommand? idle_cmd = null;
        
        // Like send_async(), need to use mutex when flushing as OutputStream must be accessed in
        // serialized fashion
        //
        // NOTE: Because this is happening in the background, it's possible for ser to go to null
        // after any yield (if a close occurs while blocking); this is why all the checking is
        // required
        int token = NonblockingMutex.INVALID_TOKEN;
        try {
            token = yield send_mutex.claim_async();
            
            // Dovecot will hang the connection (not send any replies) if IDLE is sent in the
            // same buffer as normal commands, so flush the buffer first, enqueue IDLE, and
            // flush that behind the first
            if (ser != null)
                yield ser.flush_async();
                
            // as connection is "quiet" (haven't seen new command in n msec), go into IDLE state
            // if (a) allowed by owner and (b) allowed by state machine
            if (ser != null && idle_when_quiet && issue_conditional_event(Event.SEND_IDLE)) {
                idle_cmd = new IdleCommand();
                idle_cmd.assign_tag(generate_tag());
                
                // store IDLE tag to watch for response later (many responses could arrive before it)
                bool added = posted_idle_tags.add(idle_cmd.tag);
                assert(added);
                
                Logging.debug(Logging.Flag.NETWORK, "[%s] Initiating IDLE: %s", to_string(),
                    idle_cmd.to_string());
                
                yield idle_cmd.serialize(ser);
            }
            
            if (ser != null)
                yield ser.flush_async();
        } catch (Error err) {
            idle_cmd = null;
            send_failure(err);
        } finally {
            if (token != NonblockingMutex.INVALID_TOKEN) {
                try {
                    send_mutex.release(ref token);
                } catch (Error err2) {
                    // ignored
                }
            }
        }
        
        if (idle_cmd != null)
            sent_command(idle_cmd);
    }
    
    private void check_for_connection() throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", to_string());
    }
    
    private void cmd_started_timeout() {
        timeout_cmd_count++;
        
        if (timeout_id == 0)
            timeout_id = Timeout.add_seconds(command_timeout_sec, on_cmd_timeout);
    }
    
    private void cmd_completed_timeout() {
        if (timeout_cmd_count > 0)
            timeout_cmd_count--;
        
        if (timeout_cmd_count == 0 && timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
    }
    
    private void increase_timeout() {
        if (timeout_id != 0) {
            Source.remove(timeout_id);
            timeout_id = Timeout.add_seconds(command_timeout_sec, on_cmd_timeout);
        }
    }
    
    private void cancel_timeout() {
        if (timeout_id != 0)
            Source.remove(timeout_id);
        
        timeout_id = 0;
        timeout_cmd_count = 0;
    }
    
    private bool on_cmd_timeout() {
        debug("[%s] on_cmd_timeout", to_string());
        
        // turn off graceful disconnect ... if the connection is hung, don't want to be stalled
        // trying to flush the pipe
        TcpConnection? tcp_cx = cx as TcpConnection;
        if (tcp_cx != null)
            tcp_cx.set_graceful_disconnect(false);
        
        timeout_id = 0;
        timeout_cmd_count = 0;
        
        receive_failure(new ImapError.TIMED_OUT("No response to command(s) after %u seconds",
            command_timeout_sec));
        
        return false;
    }
    
    public string to_string() {
        if (cx != null) {
            try {
                return "%04X/%s/%s".printf(cx_id,
                    Inet.address_to_string((InetSocketAddress) cx.get_remote_address()),
                    fsm.get_state_string(fsm.get_state()));
            } catch (Error err) {
                // fall through
            }
        }
        
        return "%04X/%s/%s".printf(cx_id, endpoint.to_string(), fsm.get_state_string(fsm.get_state()));
    }
    
    //
    // transition handlers
    //
    
    private bool issue_conditional_event(Event event) {
        bool proceed = false;
        fsm.issue(event, &proceed);
        
        return proceed;
    }
    
    private void signal_server_data(void *user, Object? object) {
        received_server_data((ServerData) object);
    }
    
    private void signal_status_response(void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        // stop the countdown timer on the associated command
        cmd_completed_timeout();
        
        received_status_response(status_response);
    }
    
    private void signal_continuation(void *user, Object? object) {
        received_continuation_response((ContinuationResponse) object);
    }
    
    private void signal_entered_idle() {
        in_idle(true);
    }
    
    private void signal_left_idle() {
        in_idle(false);
    }
    
    private uint do_proceed(uint state, void *user) {
        *((bool *) user) = true;
        
        return state;
    }
    
    private uint do_no_proceed(uint state, void *user) {
        *((bool *) user) = false;
        
        return state;
    }
    
    private uint on_proceed(uint state, uint event, void *user) {
        return do_proceed(state, user);
    }
    
    private uint on_no_proceed(uint state, uint event, void *user) {
        return do_no_proceed(state, user);
    }
    
    private uint on_connected(uint state, uint event, void *user) {
        // don't stay in connected state if IDLE is to be used; schedule an IDLE command (which
        // may be rescheduled if commands immediately start being issued, which they most likely
        // will)
        if (idle_when_quiet)
            reschedule_flush_timeout();
        
        return State.CONNECTED;
    }
    
    private uint on_disconnected(uint state, uint event, void *user) {
        unschedule_flush_timeout();
        
        return State.DISCONNECTED;
    }
    
    private uint on_send_idle(uint state, uint event, void *user) {
        return do_proceed(State.IDLING, user);
    }
    
    private uint on_status_response(uint state, uint event, void *user, Object? object) {
        fsm.do_post_transition(signal_status_response, user, object);
        
        return state;
    }
    
    private uint on_server_data(uint state, uint event, void *user, Object? object) {
        fsm.do_post_transition(signal_server_data, user, object);
        
        return state;
    }
    
    private uint on_continuation(uint state, uint event, void *user, Object? object) {
        fsm.do_post_transition(signal_continuation, user, object);
        
        return state;
    }
    
    private uint on_idling_continuation(uint state, uint event, void *user, Object? object) {
        ContinuationResponse continuation = (ContinuationResponse) object;
        
        Logging.debug(Logging.Flag.NETWORK, "[%s R] %s", to_string(), continuation.to_string());
        
        // only signal entering IDLE state if that's the case
        if (state != State.IDLE)
            fsm.do_post_transition(signal_entered_idle);
        
        return State.IDLE;
    }
    
    private uint on_idle_send(uint state, uint event, void *user) {
        Logging.debug(Logging.Flag.NETWORK, "[%s] Closing IDLE", to_string());
        
        // TODO: Because there is not DISCONNECTING state, need to watch for the Serializer
        // disappearing during a disconnect while in a "normal" state
        if (ser == null) {
            debug("[%s] Unable to close IDLE: no serializer", to_string());
            
            return do_no_proceed(state, user);
        }
        
        try {
            Logging.debug(Logging.Flag.NETWORK, "[%s S] %s", to_string(), "done");
            ser.push_string("done");
            ser.push_eol();
        } catch (Error err) {
            debug("[%s] Unable to close IDLE: %s", to_string(), err.message);
            
            return do_no_proceed(state, user);
        }
        
        // only signal leaving IDLE state if that's the case
        if (state == State.IDLE)
            fsm.do_post_transition(signal_left_idle);
        
        return do_proceed(State.DEIDLING, user);
    }
    
    private uint on_idle_status_response(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        // if not a post IDLE tag, then treat as external status response
        if (!posted_idle_tags.remove(status_response.tag)) {
            fsm.do_post_transition(signal_status_response, user, object);
            
            return state;
        }
        
        // StatusResponse for one of our IDLE commands; either way, no longer in IDLE mode
        if (status_response.status == Status.OK) {
            Logging.debug(Logging.Flag.NETWORK, "[%s] Leaving IDLE (%d outstanding): %s", to_string(),
                posted_idle_tags.size, status_response.to_string());
        } else {
            Logging.debug(Logging.Flag.NETWORK, "[%s] Unable to enter IDLE (%d outstanding): %s", to_string(),
                posted_idle_tags.size, status_response.to_string());
        }
        
        // Only return to CONNECTED if no other IDLE commands are outstanding (and only signal
        // if leaving IDLE state for another)
        uint next = (posted_idle_tags.size == 0) ? State.CONNECTED : state;
        
        if (state == State.IDLE && next != State.IDLE)
            fsm.do_post_transition(signal_left_idle);
        
        // If leaving IDLE for CONNECTED but user has asked to stay in IDLE whenever quiet, reschedule
        // flush (which will automatically send IDLE command)
        if (next == State.CONNECTED && idle_when_quiet)
            reschedule_flush_timeout();
        
        return next;
    }
    
    private uint on_idle_continuation(uint state, uint event, void *user, Object? object) {
        if (posted_idle_tags.size == 0) {
            debug("[%s] Bad continuation received during IDLE: %s", to_string(),
                ((ContinuationResponse) object).to_string());
        }
        
        return state;
    }
    
    private uint on_bad_transition(uint state, uint event, void *user) {
        debug("[%s] Bad cx state transition %s", to_string(), fsm.get_event_issued_string(state, event));
        
        return on_no_proceed(state, event, user);
    }
}

