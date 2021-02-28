/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientConnection : BaseObject, Logging.Source {


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
     * Default timeout to wait for another command before going idle.
     */
    public const uint DEFAULT_IDLE_TIMEOUT_SEC = 2;

    // Used solely for debugging
    private static int next_cx_id = 0;


    /**
     * Determines if the connection will use IMAP IDLE when idle.
     *
     * If //true//, when the connection is not sending commands
     * ("quiet"), it will issue an IDLE command to enter a state where
     * unsolicited server data may be sent from the server without
     * resorting to NOOP keepalives.  (Note that keepalives are still
     * required to hold the connection open, according to the IMAP
     * specification.)
     */
    public bool idle_when_quiet { get; private set; default = false; }


    /** {@inheritDoc} */
    public override string logging_domain {
        get { return ClientService.PROTOCOL_LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;

    private Geary.Endpoint endpoint;
    private int cx_id;
    private Quirks quirks;
    private IOStream? cx = null;
    private Deserializer? deserializer = null;
    private Serializer? serializer = null;

    private int tag_counter = 0;
    private char tag_prefix = 'a';

    private int64 last_seen = 0;

    private size_t bytes_accumulator = 0;

    private Geary.Nonblocking.Queue<Command> pending_queue =
        new Geary.Nonblocking.Queue<Command>.fifo();
    private Gee.Queue<Command> sent_queue = new Gee.LinkedList<Command>();
    private Command? current_command = null;
    private uint command_timeout;

    private TimeoutManager idle_timer;

    private GLib.Cancellable? open_cancellable = null;


    public virtual signal void sent_command(Command cmd) {
        debug("SEND: %s", cmd.to_string());
    }

    public virtual signal void received_status_response(StatusResponse status_response) {
        debug("RECV: %s", status_response.to_string());
    }

    public virtual signal void received_server_data(ServerData server_data) {
        debug("RECV: %s", server_data.to_string());
    }

    public virtual signal void received_continuation_response(ContinuationResponse continuation_response) {
        debug("RECV: %s", continuation_response.to_string());
    }

    public signal void received_bytes(size_t bytes);

    public signal void received_bad_response(RootParameters root,
                                                     ImapError err);

    public signal void send_failure(Error err);

    public signal void receive_failure(GLib.Error err);


    public ClientConnection(
        Geary.Endpoint endpoint,
        Quirks quirks,
        uint command_timeout = Command.DEFAULT_RESPONSE_TIMEOUT_SEC,
        uint idle_timeout_sec = DEFAULT_IDLE_TIMEOUT_SEC) {
        this.endpoint = endpoint;
        this.quirks = quirks;
        this.cx_id = next_cx_id++;
        this.command_timeout = command_timeout;
        this.idle_timer = new TimeoutManager.seconds(
            idle_timeout_sec, on_idle_timeout
        );
    }

    /** Returns the remote address of this connection, if any. */
    public GLib.SocketAddress? get_remote_address() throws GLib.Error {
        GLib.SocketAddress? addr = null;
        var tcp_cx = getTcpConnection();
        if (tcp_cx != null) {
            addr = tcp_cx.get_remote_address();
        }
        return addr;
    }

    /** Returns the local address of this connection, if any. */
    public SocketAddress? get_local_address() throws GLib.Error {
        GLib.SocketAddress? addr = null;
        var tcp_cx = getTcpConnection();
        if (tcp_cx != null) {
            addr = tcp_cx.get_local_address();
        }
        return addr;
    }

    /**
     * Determines if the connection has an outstanding IDLE command.
     */
    public bool is_in_idle() {
        return (this.current_command is IdleCommand);
    }

    /**
     * Sets whether this connection should automatically IDLE.
     *
     * If true, this will cause the connection to send an IDLE command
     * when no other commands have been sent after a short period of
     * time
     *
     * If false, any existing IDLE command will be cancelled, and the
     * connection will no longer be automatically sent.
     */
    public void enable_idle_when_quiet(bool do_idle) {
        this.idle_when_quiet = do_idle;
        if (do_idle) {
            if (!this.idle_timer.is_running) {
                this.idle_timer.start();
            }
        } else {
            cancel_idle();
        }
    }

    /**
     * Establishes a connection to the connection's endpoint.
     */
    public async void connect_async(Cancellable? cancellable = null)
        throws GLib.Error {
        if (this.cx != null) {
            throw new ImapError.ALREADY_CONNECTED("Client already connected");
        }
        this.cx = yield this.endpoint.connect_async(cancellable);

        this.pending_queue.clear();
        this.sent_queue.clear();

        try {
            yield open_channels_async();
        } catch (GLib.Error err) {
            // if this fails, need to close connection because the
            // caller will not call disconnect_async()
            try {
                yield cx.close_async();
            } catch (GLib.Error close_err) {
                // ignored
            }
            this.cx = null;

            throw err;
        }

        if (this.idle_when_quiet) {
            this.idle_timer.start();
        }
    }

    public async void disconnect_async(Cancellable? cancellable = null) throws Error {
        if (this.cx == null)
            return;

        this.idle_timer.reset();

        // To guard against reentrancy
        GLib.IOStream old_cx = this.cx;
        this.cx = null;

        // Cancel any pending commands
        foreach (Command pending in this.pending_queue.get_all()) {
            debug("Cancelling pending command: %s", pending.to_brief_string());
            pending.disconnected("Disconnected");
        }
        this.pending_queue.clear();

        // close the actual streams and the connection itself
        yield close_channels_async(cancellable);
        yield old_cx.close_async(Priority.DEFAULT, cancellable);

        var tls_cx = old_cx as GLib.TlsConnection;
        if (tls_cx != null && !tls_cx.base_io_stream.is_closed()) {
            yield tls_cx.base_io_stream.close_async(
                Priority.DEFAULT, cancellable
            );
        }
    }

    public async void starttls_async(Cancellable? cancellable = null)
        throws GLib.Error {
        if (cx == null) {
            throw new ImapError.NOT_CONNECTED(
                "Cannot start TLS when not connected"
            );
        }

        // (mostly) silent fail in this case
        if (cx is TlsClientConnection) {
            throw new ImapError.NOT_SUPPORTED(
                "Cannot start TLS when already established"
            );
        }

        // Close the Serializer/Deserializer, as need to use the TLS streams
        debug("Closing serializer to switch to TLS");
        yield close_channels_async(cancellable);

        // wrap connection with TLS connection
        this.cx = yield endpoint.starttls_handshake_async(this.cx, cancellable);

        // re-open Serializer/Deserializer with the new streams
        yield open_channels_async();
    }

    public void send_command(Command new_command)
        throws ImapError, GLib.IOError.CANCELLED {
        check_connection();
        if (new_command.should_send != null &&
            new_command.should_send.is_cancelled()) {
            new_command.cancelled_before_send();
            throw new GLib.IOError.CANCELLED(
                "Not queuing command, sending is cancelled: %s",
                new_command.to_brief_string()
            );
        }

        this.pending_queue.send(new_command);

        // Exit IDLE so we can get on with life
        cancel_idle();
    }

    /** {@inheritDoc} */
    public Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%04X/%s/%s",
            cx_id,
            endpoint.to_string(),
            this.cx != null ? "up" : "down"
        );
    }

    /**
     * Returns the command that has been sent with the given tag.
     *
     * This should be private, but is internal for the
     * ClientSession.on_received_status_response IDLE workaround.
     */
    internal Command? get_sent_command(Tag tag) {
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

    /** Sets the connection's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    private GLib.TcpConnection? getTcpConnection() {
        var cx = this.cx;
        var tls_cx = cx as GLib.TlsConnection;
        if (tls_cx != null) {
            cx = tls_cx.base_io_stream;
        }
        return cx as TcpConnection;
    }

    private async void open_channels_async() throws Error {
        this.open_cancellable = new GLib.Cancellable();

        string id = "%04d".printf(cx_id);

        var serializer_buffer = new GLib.BufferedOutputStream(
            this.cx.output_stream
        );
        serializer_buffer.set_close_base_stream(false);
        this.serializer = new Serializer(serializer_buffer);

        // Not buffering the Deserializer because it uses a
        // DataInputStream, which is already buffered
        this.deserializer = new Deserializer(
            id, this.cx.input_stream, this.quirks
        );
        this.deserializer.bytes_received.connect(on_bytes_received);
        this.deserializer.deserialize_failure.connect(on_deserialize_failure);
        this.deserializer.end_of_stream.connect(on_eos);
        this.deserializer.parameters_ready.connect(on_parameters_ready);
        this.deserializer.receive_failure.connect(on_receive_failure);
        this.deserializer.set_logging_parent(this);
        yield this.deserializer.start_async();

        // Start this running in the "background", it will stop when
        // open_cancellable is cancelled
        this.send_loop.begin();
    }

    /** Disconnect and deallocates the Serializer and Deserializer. */
    private async void close_channels_async(Cancellable? cancellable) throws Error {
        // Cancel all current and pending commands because the
        // underlying streams are going away.
        this.open_cancellable.cancel();
        foreach (Command sent in this.sent_queue) {
            debug("Cancelling sent command: %s", sent.to_brief_string());
            sent.disconnected("Connection channels closed");
        }
        this.sent_queue.clear();

        if (this.serializer != null) {
            yield this.serializer.close_stream(cancellable);
            this.serializer = null;
        }

        var deserializer = this.deserializer;
        if (deserializer != null) {
            deserializer.bytes_received.disconnect(on_bytes_received);
            deserializer.deserialize_failure.disconnect(on_deserialize_failure);
            deserializer.end_of_stream.disconnect(on_eos);
            deserializer.parameters_ready.disconnect(on_parameters_ready);
            deserializer.receive_failure.disconnect(on_receive_failure);

            yield deserializer.stop_async();
            this.deserializer = null;
        }
    }

    private inline void cancel_idle() {
        this.idle_timer.reset();
        IdleCommand? idle = this.current_command as IdleCommand;
        if (idle != null) {
            idle.exit_idle();
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
                if (!(pending is IdleCommand) || this.pending_queue.is_empty) {
                    yield flush_command(pending, cancellable);
                }

                // Check the queue is still empty after sending the
                // command, since that might have changed.
                if (this.pending_queue.is_empty) {
                    yield this.serializer.flush_stream(cancellable);
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
        if (command.should_send != null &&
            command.should_send.is_cancelled()) {
            command.cancelled_before_send();
            throw new GLib.IOError.CANCELLED(
                "Not sending command, sending is cancelled: %s",
                command.to_brief_string()
            );
        }
        GLib.Error? ser_error = null;
        try {
            // Assign a new tag; Commands with pre-assigned Tags
            // should not be re-sent. (Do this inside the critical
            // section to ensure commands go out in Tag order;
            // this is not an IMAP requirement but makes tracing
            // commands easier.)
            command.assign_tag(generate_tag());

            // Set timeout per session policy
            command.response_timeout = this.command_timeout;
            command.response_timed_out.connect(on_command_timeout);

            this.current_command = command;
            this.sent_queue.add(command);
            yield command.send(this.serializer, cancellable);
            sent_command(command);
            yield command.send_wait(this.serializer, cancellable);
        } catch (GLib.Error err) {
            ser_error = err;
        }

        this.current_command = null;

        if (ser_error != null) {
            this.sent_queue.remove(command);
            throw ser_error;
        }
    }

    private void check_connection() throws ImapError {
        if (this.cx == null) {
            throw new ImapError.NOT_CONNECTED(
                "Not connected to %s", to_string()
            );
        }
    }

    private void on_parameters_ready(RootParameters root) {
        try {
            // Important! The order of these tests matters.
            if (ContinuationResponse.is_continuation_response(root)) {
                on_continuation_response(
                    new ContinuationResponse.migrate(root, this.quirks)
                );
            } else if (StatusResponse.is_status_response(root)) {
                on_status_response(new StatusResponse.migrate(root, this.quirks));
            } else if (ServerData.is_server_data(root)) {
                on_server_data(new ServerData.migrate(root, this.quirks));
            } else {
                throw new ImapError.PARSE_ERROR(
                    "Unknown server response: %s", root.to_string()
                );
            }
        } catch (ImapError err) {
            received_bad_response(root, err);
        }

        if (this.pending_queue.is_empty && this.sent_queue.is_empty) {
            // There's nothing remaining to send, and every sent
            // command has been dealt with, so ready an IDLE command.
            if (this.idle_when_quiet) {
                this.idle_timer.start();
            }
        }
    }

    private void on_status_response(StatusResponse status)
        throws ImapError {
        // Emit this first since the code blow may throw errors
        received_status_response(status);

        if (status.is_completion) {
            Command? sent = get_sent_command(status.tag);
            if (sent == null) {
                throw new ImapError.SERVER_ERROR(
                    "Unexpected status response: %s", status.to_string()
                );
            }
            this.sent_queue.remove(sent);
            sent.response_timed_out.disconnect(on_command_timeout);
            // This could throw an error so call it after cleaning up
            sent.completed(status);
        }
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
        // the deser's bytes_received signal can be called 10's of
        // times per second, so avoid some CPU overhead by turning
        // down the number of times per second it is emitted to higher
        // levels.
        this.bytes_accumulator += bytes;
        var now = GLib.get_real_time();
        if (this.last_seen + 1000000 <= now) {
            // Touch any sent commands so they don't time out while
            // downloading large literal blocks.
            foreach (var command in this.sent_queue) {
                command.update_response_timer();
            }
            received_bytes(this.bytes_accumulator);
            this.bytes_accumulator = 0;
            this.last_seen = now;
        }
    }

    private void on_eos() {
        receive_failure(
            new ImapError.NOT_CONNECTED(
                "End of stream reading from %s", to_string()
            )
        );
    }

    private void on_receive_failure(Error err) {
        receive_failure(err);
    }

    private void on_deserialize_failure() {
        receive_failure(
            new ImapError.PARSE_ERROR(
                "Unable to deserialize from %s", to_string()
            )
        );
    }

    private void on_command_timeout(Command command) {
        this.sent_queue.remove(command);
        command.response_timed_out.disconnect(on_command_timeout);
        receive_failure(
            new ImapError.TIMED_OUT(
                "No response to command after %u seconds: %s",
                command.response_timeout,
                command.to_string()
            )
        );
    }

    private void on_idle_timeout() {
        debug("Initiating IDLE");
        try {
            this.send_command(new IdleCommand(this.open_cancellable));
        } catch (GLib.Error err) {
            warning("Error sending IDLE: %s", err.message);
        }
    }

}
