/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientConnection : BaseObject {

    /** Default un-encrypted IMAP network port */
    public const uint16 DEFAULT_PORT = 143;

    /** Default encrypted IMAP network port */
    public const uint16 DEFAULT_PORT_SSL = 993;

    /**
     * Default socket timeout duration.
     *
     * This is set to the highest value required by RFC 3501 to allow
     * for IDLE connections to remain connected even when there is no
     * traffic on them.  The side-effect is that if the physical
     * connection is dropped, no error is reported and the connection
     * won't know about it until the next send operation.
     *
     * {@link RECOMMENDED_TIMEOUT_SEC} is more realistic in that if a
     * connection is hung it's important to detect it early and drop
     * it, at the expense of more keepalive traffic.
     *
     * In general, whatever timeout is used for the ClientConnection
     * must be slightly higher than the keepalive timeout used by
     * {@link ClientSession}, otherwise the ClientConnection will be
     * dropped before the keepalive is sent.
     */
    public const uint DEFAULT_TIMEOUT_SEC = ClientSession.MAX_KEEPALIVE_SEC;

    /** Recommended socket timeout duration. */
    public const uint RECOMMENDED_TIMEOUT_SEC = ClientSession.RECOMMENDED_KEEPALIVE_SEC + 15;

    /**
     * Default timeout to wait for a server response for a command.
     */
    public const uint DEFAULT_COMMAND_TIMEOUT_SEC = 30;

    /**
     * Default timeout to wait for another command before going idle.
     */
    public const uint DEFAULT_IDLE_TIMEOUT_SEC = 2;

    // Used solely for debugging
    private static int next_cx_id = 0;


    /**
     * This identifier is used only for debugging, to differentiate connections from one another
     * in logs and debug output.
     */
    public int cx_id { get; private set; }

    /**
     * Determines if the connection will use IMAP IDLE when idle.
     *
     * If //true//, when the connection is not sending commands
     * ("quiet"), it will issue an IDLE command to enter a state where
     * unsolicited server data may be sent from the server without
     * resorting to NOOP keepalives.  (Note that keepalives are still
     * required to hold the connection open, according to the IMAP
     * specification.)
     *
     * Note that setting this false will *not* break a connection out
     * of IDLE state alone; a command needs to be flushed down the
     * pipe to do that.  (NOOP would be a good choice.)  Nor will this
     * initiate an IDLE command either; it can only do that after
     * sending a command (again, NOOP would be a good choice).
     */
    public bool idle_when_quiet = false;

    private Geary.Endpoint endpoint;
    private SocketConnection? cx = null;
    private IOStream? ios = null;
    private Serializer? ser = null;
    private BufferedOutputStream? ser_buffer = null;
    private Deserializer? des = null;

    private int tag_counter = 0;
    private char tag_prefix = 'a';

    private Geary.Nonblocking.Queue<Command> pending_queue =
        new Geary.Nonblocking.Queue<Command>.fifo();
    private Gee.Queue<Command> sent_queue = new Gee.LinkedList<Command>();
    private Command? current_command = null;

    private TimeoutManager command_timer;
    private TimeoutManager idle_timer;

    private GLib.Cancellable? open_cancellable = null;


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


    public ClientConnection(Geary.Endpoint endpoint,
                            uint command_timeout_sec = DEFAULT_COMMAND_TIMEOUT_SEC,
                            uint idle_timeout_sec = DEFAULT_IDLE_TIMEOUT_SEC) {
        this.endpoint = endpoint;
        this.cx_id = next_cx_id++;

        this.command_timer = new TimeoutManager.seconds(
            command_timeout_sec, on_command_timeout
        );
        this.idle_timer = new TimeoutManager.seconds(
            idle_timeout_sec, on_idle_timeout
        );
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
            debug("Unable to retrieve local address: %s", err.message);
        }
        
        return null;
    }

    /**
     * Determines if the connection has an outstanding IDLE command.
     */
    public bool is_in_idle() {
        return (this.current_command is IdleCommand);
    }

    /**
     * Returns silently if a connection is already established.
     */
    public async void connect_async(Cancellable? cancellable = null) throws Error {
        if (this.cx != null) {
            debug("Already connected/connecting to %s", to_string());
            return;
        }

        this.cx = yield endpoint.connect_async(cancellable);
        this.ios = cx;

        this.pending_queue.clear();
        this.sent_queue.clear();

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

            this.cx = null;
            this.ios = null;

            receive_failure(err);

            throw err;
        }

        if (this.idle_when_quiet) {
            this.idle_timer.start();
        }
    }

    public async void disconnect_async(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            return;

        this.command_timer.reset();
        this.idle_timer.reset();

        // To guard against reentrancy
        SocketConnection close_cx = cx;
        cx = null;

        // close the Serializer and Deserializer
        yield close_channels_async(cancellable);

        // close the actual streams and the connection itself
        Error? close_err = null;
        try {
            debug("[%s] Disconnecting...", to_string());
            yield ios.close_async(Priority.DEFAULT, cancellable);
            yield close_cx.close_async(Priority.DEFAULT, cancellable);
            debug("[%s] Disconnected", to_string());
        } catch (Error err) {
            debug("[%s] Error disconnecting: %s", to_string(), err.message);
            close_err = err;
        } finally {
            ios = null;

            if (close_err != null)
                close_error(close_err);

            disconnected();
        }
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
        debug("[%s] Closing serializer to switch to TLS", to_string());
        yield close_channels_async(cancellable);

        // wrap connection with TLS connection
        TlsClientConnection tls_cx = yield endpoint.starttls_handshake_async(cx, cancellable);
        
        ios = tls_cx;
        
        // re-open Serializer/Deserializer with the new streams
        yield open_channels_async();
    }

    public void send_command(Command new_command) throws ImapError {
        check_connection();

        this.pending_queue.send(new_command);

        // If the current command is an IDLE, tell it to exit so we
        // can get on with life.
        IdleCommand? idle = this.current_command as IdleCommand;
        if (idle != null) {
            idle.exit_idle();
        }
    }

    public string to_string() {
        return "%04X/%s/%s".printf(
            cx_id,
            endpoint.to_string(),
            this.cx != null ? "Connected" : "Disconnected"
        );
    }

    private async void open_channels_async() throws Error {
        assert(ios != null);
        assert(ser == null);
        assert(des == null);

        this.open_cancellable = new GLib.Cancellable();

        // Not buffering the Deserializer because it uses a DataInputStream, which is buffered
        ser_buffer = new BufferedOutputStream(ios.output_stream);
        ser_buffer.set_close_base_stream(false);

        // Use ClientConnection cx_id for debugging aid with Serializer/Deserializer
        string id = "%04d".printf(cx_id);
        ser = new Serializer(id, ser_buffer);
        des = new Deserializer(id, ios.input_stream);

        des.parameters_ready.connect(on_parameters_ready);
        des.bytes_received.connect(on_bytes_received);
        des.receive_failure.connect(on_receive_failure);
        des.deserialize_failure.connect(on_deserialize_failure);
        des.eos.connect(on_eos);

        // Start this running in the "background", it will stop when
        // open_cancellable is cancelled
        this.send_loop.begin();

        yield des.start_async();
    }

    /** Disconnect and deallocates the Serializer and Deserializer. */
    private async void close_channels_async(Cancellable? cancellable) throws Error {
        this.open_cancellable.cancel();

        // disconnect from Deserializer before yielding to stop it
        if (des != null) {
            des.parameters_ready.disconnect(on_parameters_ready);
            des.bytes_received.disconnect(on_bytes_received);
            des.receive_failure.disconnect(on_receive_failure);
            des.deserialize_failure.disconnect(on_deserialize_failure);
            des.eos.disconnect(on_eos);

            yield des.stop_async();
        }
        des = null;
        ser = null;
        // Close the Serializer's buffered stream after it as been
        // deallocated so it can't possibly write to the stream again,
        // and so the stream's async thread doesn't attempt to flush
        // its buffers from its finaliser at some later unspecified
        // point, possibly writing to an invalid underlying stream.
        if (ser_buffer != null) {
            yield ser_buffer.close_async(GLib.Priority.DEFAULT, cancellable);
            ser_buffer = null;
        }
    }

    // Generates a unique tag for the IMAP connection in the form of
    // "<a-z><000-999>".
    private Tag generate_tag() {
        // watch for odometer rollover
        if (++tag_counter >= 1000) {
            tag_counter = 0;
            tag_prefix = (tag_prefix != 'z') ? tag_prefix + 1 : 'a';
        }

        // TODO This could be optimized, but we'll leave it for now.
        return new Tag("%c%03d".printf(tag_prefix, tag_counter));
    }

    /** Long lived method to send commands as they are queued. */
    private async void send_loop() {
        while (!this.open_cancellable.is_cancelled()) {
            try {
                GLib.Cancellable cancellable = this.open_cancellable;
                Command pending = yield this.pending_queue.receive(
                    this.open_cancellable
                );

                // Only send IDLE commands if they are the last in the
                // queue, there's no point otherwise.
                bool pending_idle = pending is IdleCommand;
                if (!pending_idle || this.pending_queue.is_empty) {
                    yield flush_command(pending, cancellable);
                }

                // Check the queue is still empty after sending the
                // command, since that might have changed.
                if (this.pending_queue.is_empty) {
                    yield this.ser.flush_stream(cancellable);
                    if (this.idle_when_quiet && !pending_idle) {
                        this.idle_timer.start();
                    }
                }
            } catch (GLib.Error err) {
                if (!(err is GLib.IOError.CANCELLED)) {
                    send_failure(err);
                }
            }
        }
    }

    // Only ever call this from flush_commands, to ensure serial
    // assignment of tags and only one command gets flushed at a
    // time. This blocks asynchronously while serialising a command,
    // including while waiting for continuation request responses when
    // sending literals.
    private async void flush_command(Command command, Cancellable cancellable)
        throws GLib.Error {
        // Assign a new tag; Commands with pre-assigned Tags
        // should not be re-sent. (Do this inside the critical
        // section to ensure commands go out in Tag order;
        // this is not an IMAP requirement but makes tracing
        // commands easier.)
        command.assign_tag(generate_tag());

        this.current_command = command;
        this.sent_queue.add(command);
        GLib.Error? ser_error = null;
        try {
            yield command.serialize(this.ser, cancellable);
        } catch (GLib.Error err) {
            ser_error = err;
        }

        this.current_command = null;

        if (ser_error != null) {
            this.sent_queue.remove(command);
            throw ser_error;
        }

        // We want the timeout to trigger ASAP if the
        // connection goes away, so don't reset it if it is
        // already running.
        if (!this.command_timer.is_running) {
            this.command_timer.start();
        }

        sent_command(command);
    }

    private Command? get_sent_command(Tag tag) {
        Command? sent = null;
        if (tag.is_tagged()) {
            foreach (Command queued in this.sent_queue) {
                if (tag.equal_to(queued.tag)) {
                    sent = queued;
                    break;
                }
            }
        }
        return sent;
    }

    private void check_connection() throws ImapError {
        if (this.cx == null) {
            throw new ImapError.NOT_CONNECTED(
                "Not connected to %s", to_string()
            );
        }
    }

    private void on_parameters_ready(RootParameters root) {
        // Reset the command timer, since we know for the
        // moment that the connection is good.
        this.command_timer.reset();

        ServerResponse response;
        try {
            response = ServerResponse.migrate_from_server(root);

            StatusResponse? status = response as StatusResponse;
            if (status != null) {
                on_status_response(status);
                return;
            }

            ServerData? data = response as ServerData;
            if (data != null) {
                on_server_data(data);
                return;
            }

            ContinuationResponse? continuation = response as ContinuationResponse;
            if (continuation != null) {
                on_continuation_response(continuation);
                return;
            }
        } catch (ImapError err) {
            received_bad_response(root, err);
            return;
        }

        warning(
            "[%s] Unknown ServerResponse of type %s received: %s:",
            to_string(), response.get_type().name(),
            response.to_string()
        );
    }

    private void on_status_response(StatusResponse status)
        throws ImapError {
        if (status.is_completion) {
            Command? sent = get_sent_command(status.tag);
            if (sent == null) {
                throw new ImapError.SERVER_ERROR(
                    "Unexpected status response: %s", status.to_string()
                );
            }
            this.sent_queue.remove(sent);
            sent.completed(status);
        }

        received_status_response(status);
    }

    private void on_server_data(ServerData data)
        throws ImapError {
        Command? sent = get_sent_command(data.tag);
        if (sent != null) {
            sent.data_received(data);
        }

        received_server_data(data);
    }

    private void on_continuation_response(ContinuationResponse continuation)
        throws ImapError {
        Command? current = this.current_command;
        if (current == null) {
            throw new ImapError.SERVER_ERROR(
                "Unexpected continuation request response: %s",
                continuation.to_string()
            );
        }
        current.continuation_requested(continuation);

        received_continuation_response(continuation);
    }

    private void on_bytes_received(size_t bytes) {
        // Reset the command timer, since we know for the
        // moment that the connection is good.
        this.command_timer.reset();

        received_bytes(bytes);
    }

    private void on_receive_failure(Error err) {
        receive_failure(err);
    }

    private void on_deserialize_failure() {
        deserialize_failure(
            new ImapError.PARSE_ERROR(
                "Unable to deserialize from %s", to_string()
            )
        );
    }

    private void on_eos() {
        recv_closed();
    }

    private void on_command_timeout() {
        debug("[%s] Sending command timed out", to_string());

        // turn off graceful disconnect ... if the connection is hung,
        // don't want to be stalled trying to flush the pipe
        TcpConnection? tcp_cx = cx as TcpConnection;
        if (tcp_cx != null)
            tcp_cx.set_graceful_disconnect(false);

        receive_failure(
            new ImapError.TIMED_OUT(
                "No response to command(s) after %u seconds",
                this.command_timer.interval
            )
        );
    }

    private void on_idle_timeout() {
        Logging.debug(Logging.Flag.NETWORK, "[%s] Initiating IDLE", to_string());
        try {
            this.send_command(new IdleCommand());
        } catch (ImapError err) {
            debug("[%s] Error sending IDLE: %s", to_string(), err.message);
        }
    }

}
