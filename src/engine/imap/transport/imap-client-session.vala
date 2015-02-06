/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ClientSession : BaseObject {
    // 30 min keepalive required to maintain session
    public const uint MIN_KEEPALIVE_SEC = 30 * 60;
    
    // 10 minutes is more realistic, as underlying sockets will not necessarily report errors if
    // physical connection is lost
    public const uint RECOMMENDED_KEEPALIVE_SEC = 10 * 60;
    
    // A more aggressive keepalive will detect when a connection has died, thereby giving the client
    // a chance to reestablish a connection without long lags.
    public const uint AGGRESSIVE_KEEPALIVE_SEC = 5 * 60;
    
    // NOOP is only sent after this amount of time has passed since the last received
    // message on the connection dependent on connection state (selected/examined vs. authorized)
    public const uint DEFAULT_SELECTED_KEEPALIVE_SEC = AGGRESSIVE_KEEPALIVE_SEC;
    public const uint DEFAULT_UNSELECTED_KEEPALIVE_SEC = RECOMMENDED_KEEPALIVE_SEC;
    public const uint DEFAULT_SELECTED_WITH_IDLE_KEEPALIVE_SEC = AGGRESSIVE_KEEPALIVE_SEC;
    
    private const uint GREETING_TIMEOUT_SEC = ClientConnection.DEFAULT_COMMAND_TIMEOUT_SEC;
    
    public enum Context {
        UNCONNECTED,
        UNAUTHORIZED,
        AUTHORIZED,
        SELECTED,
        EXAMINED,
        IN_PROGRESS
    }
    
    public enum DisconnectReason {
        LOCAL_CLOSE,
        LOCAL_ERROR,
        REMOTE_CLOSE,
        REMOTE_ERROR;
        
        public bool is_error() {
            return (this == LOCAL_ERROR) || (this == REMOTE_ERROR);
        }
        
        public bool is_remote() {
            return (this == REMOTE_CLOSE) || (this == REMOTE_ERROR);
        }
    }
    
    // Many of the async commands go through the FSM, and this is used to pass state in and out of
    // the it
    private class MachineParams : Object {
        // IN
        public Command? cmd;
        
        // OUT
        public Error? err = null;
        public bool proceed = false;
        
        public MachineParams(Command? cmd) {
            this.cmd = cmd;
        }
    }
    
    // Need this because delegates with targets cannot be stored in ADTs.
    private class CommandCallback {
        public unowned SourceFunc callback;
        
        public CommandCallback(SourceFunc callback) {
            this.callback = callback;
        }
    }
    
    private class SendCommandOperation : Nonblocking.BatchOperation {
        // IN
        public ClientSession owner;
        public Command cmd;
        
        // OUT
        public StatusResponse response;
        
        public SendCommandOperation(ClientSession owner, Command cmd) {
            this.owner = owner;
            this.cmd = cmd;
        }
        
        public override async Object? execute_async(Cancellable? cancellable) throws Error {
            response = yield owner.command_transaction_async(cmd, cancellable);
            
            return response;
        }
    }
    
    private enum State {
        // canonical IMAP session states
        UNCONNECTED,
        NOAUTH,
        AUTHORIZED,
        SELECTED,
        LOGGED_OUT,
        
        // transitional states
        CONNECTING,
        AUTHORIZING,
        SELECTING,
        CLOSING_MAILBOX,
        LOGGING_OUT,
        
        // terminal state
        BROKEN,
        
        COUNT
    }
    
    private static string state_to_string(uint state) {
        return ((State) state).to_string();
    }
    
    private enum Event {
        // user-initiated events
        CONNECT,
        LOGIN,
        SEND_CMD,
        SELECT,
        CLOSE_MAILBOX,
        LOGOUT,
        DISCONNECT,
        
        // server events
        CONNECTED,
        DISCONNECTED,
        RECV_STATUS,
        RECV_COMPLETION,
        
        // I/O errors
        RECV_ERROR,
        SEND_ERROR,
        
        TIMEOUT,
        
        COUNT;
    }
    
    private static string event_to_string(uint event) {
        return ((Event) event).to_string();
    }
    
    private static Geary.State.MachineDescriptor machine_desc = new Geary.State.MachineDescriptor(
        "Geary.Imap.ClientSession", State.UNCONNECTED, State.COUNT, Event.COUNT,
        state_to_string, event_to_string);
    
    /**
     * {@link ClientSession} tracks server extensions reported via the CAPABILITY server data
     * response.
     *
     * ClientSession stores the last seen list as a service for users and uses it internally
     * (specifically for IDLE support).
     */
    public Capabilities capabilities { get; private set; default = new Capabilities(0); }
    
    private Endpoint imap_endpoint;
    private Geary.State.Machine fsm;
    private ClientConnection? cx = null;
    private MailboxSpecifier? current_mailbox = null;
    private bool current_mailbox_readonly = false;
    private Gee.HashMap<Tag, StatusResponse> seen_completion_responses = new Gee.HashMap<
        Tag, StatusResponse>();
    private Gee.HashMap<Tag, CommandCallback> waiting_for_completion = new Gee.HashMap<
        Tag, CommandCallback>();
    private int next_capabilities_revision = 1;
    private uint keepalive_id = 0;
    private uint selected_keepalive_secs = 0;
    private uint unselected_keepalive_secs = 0;
    private uint selected_with_idle_keepalive_secs = 0;
    private bool allow_idle = true;
    private Command? state_change_cmd = null;
    private Nonblocking.Semaphore? connect_waiter = null;
    private Error? connect_err = null;
    
    //
    // Connection state changes
    //
    
    public signal void connected();
    
    public signal void session_denied(string? reason);
    
    public signal void authorized();
    
    public signal void logged_out();
    
    public signal void login_failed();
    
    public signal void disconnected(DisconnectReason reason);
    
    public signal void status_response_received(StatusResponse status_response);
    
    /**
     * Fired before the specific {@link ServerData} signals (i.e. {@link capability}, {@link exists}
     * {@link expunge}, etc.)
     */
    public signal void server_data_received(ServerData server_data);
    
    public signal void capability(Capabilities capabilities);
    
    public signal void exists(int count);
    
    public signal void expunge(SequenceNumber seq_num);
    
    public signal void fetch(FetchedData fetched_data);
    
    public signal void flags(MailboxAttributes mailbox_attrs);
    
    /**
     * Fired when a LIST or XLIST {@link ServerData} is returned from the server.
     */
    public signal void list(MailboxInformation mailbox_info);
    
    // TODO: LSUB results
    
    public signal void recent(int count);
    
    public signal void search(int64[] seq_or_uid);
    
    public signal void status(StatusData status_data);
    
    /**
     * If the mailbox name is null it indicates the type of state change that has occurred
     * (authorized -> selected/examined or vice-versa).  If new_name is null readonly should be
     * ignored.
     */
    public signal void current_mailbox_changed(MailboxSpecifier? old_name, MailboxSpecifier? new_name,
        bool readonly);
    
    public ClientSession(Endpoint imap_endpoint) {
        this.imap_endpoint = imap_endpoint;
        
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.UNCONNECTED, Event.CONNECT, on_connect),
            new Geary.State.Mapping(State.UNCONNECTED, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.UNCONNECTED, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.UNCONNECTED, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.UNCONNECTED, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.UNCONNECTED, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.UNCONNECTED, Event.DISCONNECT, Geary.State.nop),
            
            new Geary.State.Mapping(State.CONNECTING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.CONNECTING, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.CONNECTING, Event.CONNECTED, on_connected),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_STATUS, on_connecting_recv_status),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_ERROR, on_connecting_send_recv_error),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_ERROR, on_connecting_send_recv_error),
            new Geary.State.Mapping(State.CONNECTING, Event.TIMEOUT, on_connecting_timeout),
            
            new Geary.State.Mapping(State.NOAUTH, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGIN, on_login),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.NOAUTH, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.NOAUTH, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_COMPLETION, on_recv_status),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.AUTHORIZING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGIN, on_logging_in),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_CMD, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_COMPLETION, on_login_recv_completion),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.AUTHORIZED, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.AUTHORIZED, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.AUTHORIZED, Event.CLOSE_MAILBOX, on_not_selected),
            new Geary.State.Mapping(State.AUTHORIZED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_COMPLETION, on_recv_status),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.SELECTING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.SELECTING, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTING, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTING, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_COMPLETION, on_selecting_recv_completion),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.SELECTED, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.SELECTED, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.SELECTED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTED, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_COMPLETION, on_recv_status),
            new Geary.State.Mapping(State.SELECTED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SELECT, on_select),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CLOSE_MAILBOX, on_not_selected),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_COMPLETION, on_closing_recv_completion),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.LOGGING_OUT, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.LOGOUT, Geary.State.nop),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_COMPLETION, on_logging_out_recv_completion),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_ERROR, on_recv_error),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_ERROR, on_recv_error),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.BROKEN, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECTED, Geary.State.nop),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.BROKEN, Event.SEND_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_ERROR, Geary.State.nop),
        };
        
        fsm = new Geary.State.Machine(machine_desc, mappings, on_ignored_transition);
        fsm.set_logging(false);
    }
    
    ~ClientSession() {
        switch (fsm.get_state()) {
            case State.UNCONNECTED:
            case State.BROKEN:
                // no problem-o
            break;
            
            default:
                error("[%s] ClientSession ref dropped while still active", to_string());
        }
        
        debug("DTOR: ClientSession %s", to_string());
    }
    
    public MailboxSpecifier? get_current_mailbox() {
        return current_mailbox;
    }
    
    public bool is_current_mailbox_readonly() {
        return current_mailbox_readonly;
    }
    
    public Context get_context(out MailboxSpecifier? current_mailbox) {
        current_mailbox = null;
        
        switch (fsm.get_state()) {
            case State.UNCONNECTED:
            case State.LOGGED_OUT:
            case State.LOGGING_OUT:
            case State.BROKEN:
                return Context.UNCONNECTED;
            
            case State.NOAUTH:
                return Context.UNAUTHORIZED;
            
            case State.AUTHORIZED:
                return Context.AUTHORIZED;
            
            case State.SELECTED:
                current_mailbox = this.current_mailbox;
                
                return current_mailbox_readonly ? Context.EXAMINED : Context.SELECTED;
            
            case State.CONNECTING:
            case State.AUTHORIZING:
            case State.SELECTING:
            case State.CLOSING_MAILBOX:
                return Context.IN_PROGRESS;
            
            default:
                assert_not_reached();
        }
    }
    
    // Some commands require waiting for a completion response in order to shift the state machine's
    // State; this allocates such a wait, returning false if another command is outstanding also
    // waiting for one to finish
    private bool reserve_state_change_cmd(MachineParams params, uint state, uint event) {
        if (state_change_cmd != null || params.cmd == null) {
            params.proceed = false;
            params.err = new ImapError.NOT_SUPPORTED("Cannot perform operation %s while session is %s",
                fsm.get_event_string(event), fsm.get_state_string(state));
            
            return false;
        }
        
        state_change_cmd = params.cmd;
        params.proceed = true;
        
        return true;
    }
    
    // This is the complement to reserve_state_change_cmd(), returning true if the response represents
    // the pending state change Command (and clearing it if it is)
    private bool validate_state_change_cmd(ServerResponse response, out Command? cmd = null) {
        cmd = state_change_cmd;
        
        if (state_change_cmd == null || !state_change_cmd.tag.equal_to(response.tag))
            return false;
        
        state_change_cmd = null;
        
        return true;
    }
    
    //
    // connect
    //
    
    /**
     * Connect to the server.
     *
     * This performs no transaction or session initiation with the server.  See {@link login_async}
     * and {@link initiate_session_async} for next steps.
     *
     * The signals {@link connected} or {@link session_denied} will be fired in the context of this
     * call, depending on the results of the connection greeting from the server.  However,
     * command should only be transmitted (login, initiate session, etc.) after this call has
     * completed.
     *
     * If the connection fails (if this call throws an Error) the ClientSession will be disconnected,
     * even if the error was from the server (that is, not a network problem).  The
     * {@link ClientSession} should be discarded.
     */
    public async void connect_async(Cancellable? cancellable = null) throws Error {
        MachineParams params = new MachineParams(null);
        fsm.issue(Event.CONNECT, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        // ClientConnection and the connection waiter should exist at this point
        assert(cx != null);
        assert(connect_waiter != null);
        
        // connect and let ClientConnection's signals drive the show
        try {
            yield cx.connect_async(cancellable);
        } catch (Error err) {
            fsm.issue(Event.SEND_ERROR, null, null, err);
            
            throw err;
        }
        
        // set up timer to wait for greeting from server
        Scheduler.Scheduled timeout = Scheduler.after_sec(GREETING_TIMEOUT_SEC, on_greeting_timeout);
        
        // wait for the initial greeting or a timeout ... this prevents the caller from turning
        // around and issuing a command while still in CONNECTING state
        yield connect_waiter.wait_async(cancellable);
        
        // cancel the timeout, if it's not already fired
        timeout.cancel();
        
        // if session was denied or timeout, ensure the session is disconnected and throw the
        // original Error ... connect_async shouldn't leave the session in a LOGGED_OUT state,
        // but completely disconnected if unsuccessful
        if (connect_err != null) {
            try {
                yield disconnect_async(cancellable);
            } catch (Error err) {
                debug("[%s] Error disconnecting after a failed connect attempt: %s", to_string(),
                    err.message);
            }
            
            throw connect_err;
        }
    }
    
    private bool on_greeting_timeout() {
        // if still in CONNECTING state, the greeting never arrived
        if (fsm.get_state() == State.CONNECTING)
            fsm.issue(Event.TIMEOUT);
        
        return false;
    }
    
    private uint on_connect(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(cx == null);
        cx = new ClientConnection(imap_endpoint);
        cx.connected.connect(on_network_connected);
        cx.disconnected.connect(on_network_disconnected);
        cx.sent_command.connect(on_network_sent_command);
        cx.send_failure.connect(on_network_send_error);
        cx.received_status_response.connect(on_received_status_response);
        cx.received_server_data.connect(on_received_server_data);
        cx.received_bytes.connect(on_received_bytes);
        cx.received_bad_response.connect(on_received_bad_response);
        cx.recv_closed.connect(on_received_closed);
        cx.receive_failure.connect(on_network_receive_failure);
        cx.deserialize_failure.connect(on_network_receive_failure);
        
        assert(connect_waiter == null);
        connect_waiter = new Nonblocking.Semaphore();
        
        // only use IDLE when in SELECTED or EXAMINED state
        cx.set_idle_when_quiet(false);
        
        params.proceed = true;
        
        return State.CONNECTING;
    }
    
    // this is used internally to tear-down the ClientConnection object and unhook it from
    // ClientSession
    private void drop_connection() {
        unschedule_keepalive();
        
        if (cx != null) {
            cx.connected.disconnect(on_network_connected);
            cx.disconnected.disconnect(on_network_disconnected);
            cx.sent_command.disconnect(on_network_sent_command);
            cx.send_failure.disconnect(on_network_send_error);
            cx.received_status_response.disconnect(on_received_status_response);
            cx.received_server_data.disconnect(on_received_server_data);
            cx.received_bytes.disconnect(on_received_bytes);
            cx.received_bad_response.disconnect(on_received_bad_response);
            cx.recv_closed.disconnect(on_received_closed);
            cx.receive_failure.disconnect(on_network_receive_failure);
            cx.deserialize_failure.disconnect(on_network_receive_failure);
            
            cx = null;
        }
        
        // if there are any outstanding commands waiting for responses, wake them up now
        if (waiting_for_completion.size > 0) {
            debug("[%s] Cancelling %d pending commands", to_string(), waiting_for_completion.size);
            foreach (CommandCallback cmd_cb in waiting_for_completion.values)
                Scheduler.on_idle(cmd_cb.callback);
            
            waiting_for_completion.clear();
        }
    }
    
    private uint on_connected(uint state, uint event) {
        debug("[%s] Connected", to_string());
        
        // stay in current state -- wait for initial status response to move into NOAUTH or LOGGED OUT
        return state;
    }
    
    private uint on_connecting_recv_status(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        // see on_connected() why signals and semaphore are delayed for this event
        try {
            connect_waiter.notify();
        } catch (Error err) {
            message("[%s] Unable to notify connect_waiter of connection: %s", to_string(),
                err.message);
        }
        
        if (status_response.status == Status.OK) {
            fsm.do_post_transition(() => { connected(); });
            
            return State.NOAUTH;
        }
        
        debug("[%s] Connect denied: %s", to_string(), status_response.to_string());
        
        fsm.do_post_transition(() => { session_denied(status_response.get_text()); });
        connect_err = new ImapError.SERVER_ERROR("Session denied: %s", status_response.get_text());
        
        return State.LOGGED_OUT;
    }
    
    private uint on_connecting_timeout(uint state, uint event) {
        // wake up the waiting task in connect_async
        try {
            connect_waiter.notify();
        } catch (Error err) {
            message("[%s] Unable to notify connect_waiter of timeout: %s", to_string(),
                err.message);
        }
        
        debug("[%s] Connect timed-out", to_string());
        
        connect_err = new IOError.TIMED_OUT("Session greeting not seen in %u seconds",
            GREETING_TIMEOUT_SEC);
        
        return State.LOGGED_OUT;
    }
    
    //
    // login
    //
    
    /**
     * Performs the LOGIN command using the supplied credentials.
     *
     * @see initiate_session_async
     */
    public async StatusResponse login_async(Geary.Credentials credentials, Cancellable? cancellable = null)
        throws Error {
        if (!credentials.is_complete()) {
            login_failed();
            throw new ImapError.UNAUTHENTICATED("No credentials provided for account: %s", credentials.to_string());
        }
        
        LoginCommand cmd = new LoginCommand(credentials.user, credentials.pass);
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.LOGIN, null, params);
        
        if (params.err != null)
            throw params.err;
        
        // should always proceed; only an Error could change this
        assert(params.proceed);
        
        return yield command_transaction_async(cmd, cancellable);
    }
    
    /**
     * Prepares the connection and performs a login using the supplied credentials.
     *
     * Preparing the connnection includes attempting compression and using STARTTLS if necessary.
     * {@link Capabilities} are also retrieved automatically at the right time to ensure the best
     * results are available with {@link capabilities}.
     */
    public async void initiate_session_async(Geary.Credentials credentials, Cancellable? cancellable = null)
        throws Error {
        // If no capabilities available, get them now
        if (capabilities.is_empty())
            yield send_command_async(new CapabilityCommand());
        
        // store them for comparison later
        Imap.Capabilities caps = capabilities;
        
        debug("[%s] use_starttls=%s is_ssl=%s starttls=%s", to_string(), imap_endpoint.use_starttls.to_string(),
            imap_endpoint.is_ssl.to_string(), caps.has_capability(Capabilities.STARTTLS).to_string());
        switch (imap_endpoint.attempt_starttls(caps.has_capability(Capabilities.STARTTLS))) {
            case Endpoint.AttemptStarttls.YES:
                debug("[%s] Attempting STARTTLS...", to_string());
                StatusResponse resp;
                try {
                    resp = yield send_command_async(new StarttlsCommand());
                } catch (Error err) {
                    debug("Error attempting STARTTLS command on %s: %s", to_string(), err.message);
                    
                    throw err;
                }
                
                if (resp.status == Status.OK) {
                    yield cx.starttls_async(cancellable);
                    debug("[%s] STARTTLS completed", to_string());
                } else {
                    debug("[%s} STARTTLS refused: %s", to_string(), resp.status.to_string());
                    
                    // throw an exception and fail rather than send credentials under suspect
                    // conditions
                    throw new ImapError.NOT_SUPPORTED("STARTTLS refused by %s: %s", to_string(),
                        resp.status.to_string());
                }
            break;
            
            case Endpoint.AttemptStarttls.NO:
                debug("[%s] No STARTTLS attempted", to_string());
            break;
            
            case Endpoint.AttemptStarttls.HALT:
                throw new ImapError.NOT_SUPPORTED("STARTTLS unavailable for %s", to_string());
            
            default:
                assert_not_reached();
        }
        
        // Login after STARTTLS
        StatusResponse login_resp = yield login_async(credentials, cancellable);
        if (login_resp.status != Status.OK) {
            throw new ImapError.UNAUTHENTICATED("Unable to login to %s with supplied credentials",
                to_string());
        }
        
        // if new capabilities not offered after login, get them now
        if (caps.revision == capabilities.revision)
            yield send_command_async(new CapabilityCommand());
        
        // either way, new capabilities should be available
        caps = capabilities;
        
        // Attempt compression (usually only available after authentication)
        if (caps.has_setting(Capabilities.COMPRESS, Capabilities.DEFLATE_SETTING)) {
            StatusResponse resp = yield send_command_async(
                new CompressCommand(CompressCommand.ALGORITHM_DEFLATE));
            if (resp.status == Status.OK) {
                install_send_converter(new ZlibCompressor(ZlibCompressorFormat.RAW));
                install_recv_converter(new ZlibDecompressor(ZlibCompressorFormat.RAW));
                debug("[%s] Compression started", to_string());
            } else {
                debug("[%s] Unable to start compression: %s", to_string(), resp.to_string());
            }
        } else {
            debug("[%s] No compression available", to_string());
        }
    }
    
    private uint on_login(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(params.cmd is LoginCommand);
        if (!reserve_state_change_cmd(params, state, event))
            return state;
        
        return State.AUTHORIZING;
    }
    
    private uint on_logging_in(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.err = new ImapError.ALREADY_CONNECTED("Already logging in to %s", to_string());
        
        return state;
    }
    
    private uint on_login_recv_completion(uint state, uint event, void *user, Object? object) {
        StatusResponse completion_response = (StatusResponse) object;
        
        if (!validate_state_change_cmd(completion_response))
            return state;
        
        // Remember: only you can prevent firing signals inside state transition handlers
        switch (completion_response.status) {
            case Status.OK:
                fsm.do_post_transition(() => { authorized(); });
                
                return State.AUTHORIZED;
            
            default:
                debug("[%s] Unable to LOGIN: %s", to_string(), completion_response.to_string());
                fsm.do_post_transition(() => { login_failed(); });
                
                return State.NOAUTH;
        }
    }
    
    //
    // keepalives (nop idling to keep the session alive and to periodically receive notifications
    // of changes)
    //
    
    /**
     * If seconds is negative or zero, keepalives will be disabled.  (This is not recommended.)
     *
     * Although keepalives can be enabled at any time, if they're enabled and trigger sending
     * a command prior to connection, error signals may be fired.
     */
    public void enable_keepalives(uint seconds_while_selected,
        uint seconds_while_unselected, uint seconds_while_selected_with_idle) {
        selected_keepalive_secs = seconds_while_selected;
        selected_with_idle_keepalive_secs = seconds_while_selected_with_idle;
        unselected_keepalive_secs = seconds_while_unselected;
        
        // schedule one now, although will be rescheduled if traffic is received before it fires
        schedule_keepalive();
    }
    
    /**
     * Returns true if keepalives are disactivated, false if already disabled.
     */
    public bool disable_keepalives() {
        return unschedule_keepalive();
    }
    
    private bool unschedule_keepalive() {
        if (keepalive_id == 0)
            return false;
        
        Source.remove(keepalive_id);
        keepalive_id = 0;
        
        return true;
    }
    
    /**
     * If enabled, an IDLE command will be used for notification of unsolicited server data whenever
     * a mailbox is selected or examined.  IDLE will only be used if ClientSession has seen a
     * CAPABILITY server data response with IDLE listed as a supported extension.
     *
     * This will *not* break a connection out of IDLE mode; a command must be sent as well to force
     * the connection back to de-idled state.
     *
     * Note that this overrides other heuristics ClientSession uses about allowing idle, so use
     * with caution.
     */
    public void allow_idle_when_selected(bool allow_idle) {
        this.allow_idle = allow_idle;
    }
    
    private void schedule_keepalive() {
        // if old one was scheduled, unschedule and schedule anew
        unschedule_keepalive();
        
        uint seconds;
        switch (get_context(null)) {
            case Context.UNCONNECTED:
                return;
            
            case Context.IN_PROGRESS:
            case Context.EXAMINED:
            case Context.SELECTED:
                seconds = (allow_idle && supports_idle()) ? selected_with_idle_keepalive_secs
                    : selected_keepalive_secs;
            break;
            
            case Context.UNAUTHORIZED:
            case Context.AUTHORIZED:
            default:
                seconds = unselected_keepalive_secs;
            break;
        }
        
        // Possible to not have keepalives in one state but in another, or for neither
        //
        // Yes, we allow keepalive to be set to 1 second.  It's their dime.
        if (seconds > 0)
            keepalive_id = Timeout.add_seconds(seconds, on_keepalive);
    }
    
    private bool on_keepalive() {
        // by returning false, this will not automatically be called again, so the SourceFunc
        // is now dead
        keepalive_id = 0;
        
        send_command_async.begin(new NoopCommand(), null, on_keepalive_completed);
        Logging.debug(Logging.Flag.PERIODIC, "[%s] Sending keepalive...", to_string());
        
        // No need to reschedule keepalive, as the notification that the command was sent should
        // do that automatically
        
        return false;
    }
    
    private void on_keepalive_completed(Object? source, AsyncResult result) {
        try {
            StatusResponse response = send_command_async.end(result);
            Logging.debug(Logging.Flag.PERIODIC, "[%s] Keepalive result: %s", to_string(),
                response.to_string());
        } catch (Error err) {
            debug("[%s] Keepalive error: %s", to_string(), err.message);
        }
    }
    
    //
    // Converters
    //
    
    public bool install_send_converter(Converter converter) {
        return (cx != null) ? cx.install_send_converter(converter) : false;
    }
    
    public bool install_recv_converter(Converter converter) {
        return (cx != null) ? cx.install_recv_converter(converter) : false;
    }
    
    public bool supports_idle() {
        return capabilities.has_capability(Capabilities.IDLE);
    }
    
    //
    // send commands
    //
    
    public async StatusResponse send_command_async(Command cmd, Cancellable? cancellable = null) 
        throws Error {
        check_unsupported_send_command(cmd);
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.SEND_CMD, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        return yield command_transaction_async(cmd, cancellable);
    }
    
    public async Gee.Map<Command, StatusResponse> send_multiple_commands_async(
        Gee.Collection<Command> cmds, Cancellable? cancellable = null) throws Error {
        if (cmds.size == 0)
            throw new ImapError.INVALID("Must supply at least one command");
        
        foreach (Command cmd in cmds)
            check_unsupported_send_command(cmd);
        
        // only issue one event to the state machine for all commands; either all succeed or all fail
        MachineParams params = new MachineParams(Geary.Collection.get_first(cmds));
        fsm.issue(Event.SEND_CMD, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        // Issue all at once using a Nonblocking.Batch
        Nonblocking.Batch batch = new Nonblocking.Batch();
        foreach (Command cmd in cmds)
            batch.add(new SendCommandOperation(this, cmd));
        
        yield batch.execute_all_async(cancellable);
        batch.throw_first_exception();
        
        Gee.Map<Command, StatusResponse> map = new Gee.HashMap<Command, StatusResponse>();
        foreach (int id in batch.get_ids()) {
            SendCommandOperation op = (SendCommandOperation) batch.get_operation(id);
            map.set(op.cmd, op.response);
        }
        
        return map;
    }
    
    private void check_unsupported_send_command(Command cmd) throws Error {
        // look for special commands that we wish to handle directly, as they affect the state
        // machine
        //
        // TODO: Convert commands into proper calls to avoid throwing an exception
        if (cmd.has_name(LoginCommand.NAME)
            || cmd.has_name(LogoutCommand.NAME)
            || cmd.has_name(SelectCommand.NAME)
            || cmd.has_name(ExamineCommand.NAME)
            || cmd.has_name(CloseCommand.NAME)) {
            throw new ImapError.NOT_SUPPORTED("Use direct calls rather than commands for %s", cmd.name);
        }
    }
    
    private uint on_send_command(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.proceed = true;
        
        return state;
    }
    
    private uint on_recv_status(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        switch (status_response.status) {
            case Status.OK:
                // some good-feeling text that doesn't need to be handled when in this state
            break;
            
            case Status.BYE:
                debug("[%s] Received BYE from server: %s", to_string(), status_response.to_string());
                
                // nothing more we can do; drop connection and report disconnect to user
                cx.disconnect_async.begin(null, on_bye_disconnect_completed);
                
                state = State.BROKEN;
            break;
            
            default:
                debug("[%s] Received error from server: %s", to_string(), status_response.to_string());
            break;
        }
        
        return state;
    }
    
    private void on_bye_disconnect_completed(Object? source, AsyncResult result) {
        dispatch_disconnect_results(DisconnectReason.REMOTE_CLOSE, result);
    }
    
    //
    // select/examine
    //
    
    public async StatusResponse select_async(MailboxSpecifier mailbox, Cancellable? cancellable = null) 
        throws Error {
        return yield select_examine_async(mailbox, true, cancellable);
    }
    
    public async StatusResponse examine_async(MailboxSpecifier mailbox, Cancellable? cancellable = null)
        throws Error {
        return yield select_examine_async(mailbox, false, cancellable);
    }
    
    public async StatusResponse select_examine_async(MailboxSpecifier mailbox, bool is_select,
        Cancellable? cancellable) throws Error {
        // Ternary troubles
        Command cmd;
        if (is_select)
            cmd = new SelectCommand(mailbox);
        else
            cmd = new ExamineCommand(mailbox);
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.SELECT, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        return yield command_transaction_async(cmd, cancellable);
    }
    
    private uint on_select(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        if (!reserve_state_change_cmd(params, state, event))
            return state;
        
        // Allow IDLE *before* issuing SELECT/EXAMINE because there's no guarantee another command
        // will be issued any time soon, which is necessary for the IDLE command to be tacked on
        // to the end of it.  In other words, telling ClientConnection to go into IDLE after the
        // SELECT/EXAMINE command is too late unless another command is sent (set_idle_when_quiet()
        // performs no I/O).
        cx.set_idle_when_quiet(allow_idle && supports_idle());
        
        return State.SELECTING;
    }
    
    private uint on_not_selected(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.err = new ImapError.INVALID("Can't close mailbox, not selected");
        
        return state;
    }
    
    private uint on_selecting_recv_completion(uint state, uint event, void *user, Object? object) {
        StatusResponse completion_response = (StatusResponse) object;
        
        Command? cmd;
        if (!validate_state_change_cmd(completion_response, out cmd))
            return state;
        
        // get the mailbox from the command
        MailboxSpecifier? mailbox = null;
        if (cmd is SelectCommand) {
            mailbox = ((SelectCommand) cmd).mailbox;
            current_mailbox_readonly = false;
        } else if (cmd is ExamineCommand) {
            mailbox = ((ExamineCommand) cmd).mailbox;
            current_mailbox_readonly = true;
        }
        
        // should only get to this point if cmd was SELECT or EXAMINE
        assert(mailbox != null);
        
        switch (completion_response.status) {
            case Status.OK:
                // mailbox is SELECTED/EXAMINED, report change after completion of transition
                MailboxSpecifier? old_mailbox = current_mailbox;
                current_mailbox = mailbox;
                
                if (old_mailbox != current_mailbox)
                    fsm.do_post_transition(notify_select_completed, null, old_mailbox);
                
                return State.SELECTED;
            
            default:
                debug("[%s]: Unable to SELECT/EXAMINE: %s", to_string(), completion_response.to_string());
                
                // turn off IDLE, not entering SELECTED/EXAMINED state
                cx.set_idle_when_quiet(false);
                
                return State.AUTHORIZED;
        }
    }
    
    private void notify_select_completed(void *user, Object? object) {
        current_mailbox_changed((MailboxSpecifier) object, current_mailbox, current_mailbox_readonly);
    }
    
    //
    // close mailbox
    //
    
    public async StatusResponse close_mailbox_async(Cancellable? cancellable = null) throws Error {
        CloseCommand cmd = new CloseCommand();
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.CLOSE_MAILBOX, null, params);
        
        if (params.err != null)
            throw params.err;
        
        return yield command_transaction_async(cmd, cancellable);
    }
    
    private uint on_close_mailbox(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(params.cmd is CloseCommand);
        if (!reserve_state_change_cmd(params, state, event))
            return state;
        
        // returning to AUTHORIZED state, turn off IDLE
        cx.set_idle_when_quiet(false);
        
        return State.CLOSING_MAILBOX;
    }
    
    private uint on_closing_recv_completion(uint state, uint event, void *user, Object? object) {
        StatusResponse completion_response = (StatusResponse) object;
        
        if (!validate_state_change_cmd(completion_response))
            return state;
        
        switch (completion_response.status) {
            case Status.OK:
                MailboxSpecifier? old_mailbox = current_mailbox;
                current_mailbox = null;
                
                if (old_mailbox != null)
                    fsm.do_post_transition(notify_mailbox_closed, null, old_mailbox);
                
                return State.AUTHORIZED;
            
            default:
                debug("[%s] Unable to CLOSE: %s", to_string(), completion_response.to_string());
                
                return State.SELECTED;
        }
    }
    
    private void notify_mailbox_closed(void *user, Object? object) {
        current_mailbox_changed((MailboxSpecifier) object, null, false);
    }
    
    //
    // logout
    //
    
    public async void logout_async(Cancellable? cancellable = null) throws Error {
        LogoutCommand cmd = new LogoutCommand();
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.LOGOUT, null, params);
        
        if (params.err != null)
            throw params.err;
        
        if(params.proceed)
            yield command_transaction_async(cmd, cancellable);
    }
    
    private uint on_logout(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(params.cmd is LogoutCommand);
        if (!reserve_state_change_cmd(params, state, event))
            return state;
        
        return State.LOGGING_OUT;
    }
    
    private uint on_logging_out_recv_completion(uint state, uint event, void *user, Object? object) {
        StatusResponse completion_response = (StatusResponse) object;
        
        if (!validate_state_change_cmd(completion_response))
            return state;
        
        fsm.do_post_transition(() => { logged_out(); });
        
        return State.LOGGED_OUT;
    }
    
    //
    // disconnect
    //
    
    public async void disconnect_async(Cancellable? cancellable = null) throws Error {
        MachineParams params = new MachineParams(null);
        fsm.issue(Event.DISCONNECT, null, params);
        
        if (params.err != null)
            throw params.err;
        
        if (!params.proceed)
            return;
        
        Error? disconnect_err = null;
        try {
            yield cx.disconnect_async(cancellable);
        } catch (Error err) {
            disconnect_err = err;
        }
        
        drop_connection();
        disconnected(DisconnectReason.LOCAL_CLOSE);
        
        if (disconnect_err != null)
            throw disconnect_err;
    }
    
    private uint on_disconnect(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.proceed = true;
        
        return State.BROKEN;
    }
    
    //
    // error handling
    //
    
    // use different error handler when connecting because, if connect_async() fails, there's no
    // requirement for the user to call disconnect_async() and clean up... this prevents leaving the
    //  FSM in the CONNECTING state, causing an assertion when this object is destroyed
    private uint on_connecting_send_recv_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        
        debug("[%s] Connecting send/recv error, dropping client connection: %s", to_string(), err.message);
        
        fsm.do_post_transition(() => { drop_connection(); });
        
        return State.BROKEN;
    }
    
    private uint on_send_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        
        if (err is IOError.CANCELLED)
            return state;
        
        debug("[%s] Send error, disconnecting: %s", to_string(), err.message);
        
        cx.disconnect_async.begin(null, on_fire_send_error_signal);
        
        return State.BROKEN;
    }
    
    private void on_fire_send_error_signal(Object? object, AsyncResult result) {
        dispatch_disconnect_results(DisconnectReason.LOCAL_ERROR, result);
    }
    
    private uint on_recv_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        debug("[%s] Receive error, disconnecting: %s", to_string(), err.message);
        
        cx.disconnect_async.begin(null, on_fire_recv_error_signal);
        
        return State.BROKEN;
    }
    
    private void on_fire_recv_error_signal(Object? object, AsyncResult result) {
        dispatch_disconnect_results(DisconnectReason.REMOTE_ERROR, result);
    }
    
    private void dispatch_disconnect_results(DisconnectReason reason, AsyncResult result) {
        debug("[%s] Disconnected due to %s", to_string(), reason.to_string());
        
        try {
            cx.disconnect_async.end(result);
        } catch (Error err) {
            debug("[%s] Send/recv disconnect failed: %s", to_string(), err.message);
        }
        
        drop_connection();
        
        disconnected(reason);
    }
    
    // This handles the situation where the user submits a command before the connection has been
    // established
    private uint on_early_command(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.NOT_CONNECTED("Command %s too early: not connected to %s",
            params.cmd.name, to_string());
        
        return state;
    }
    
    // This handles the situation where the user submits a command after the connection has been
    // logged out, terminated, or errored-out
    private uint on_late_command(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.NOT_CONNECTED("Connection to %s closing or closed", to_string());
        
        return state;
    }
    
    private uint on_already_connected(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.ALREADY_CONNECTED("Already connected or connecting to %s", to_string());
        
        return state;
    }
    
    private uint on_already_logged_in(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.ALREADY_CONNECTED("Already logged in to %s", to_string());
        
        return state;
    }
    
    // This handles the situation where an unanticipated (or uninteresting) ServerResponse was received
    private uint on_dropped_response(uint state, uint event, void *user, Object? object) {
        ServerResponse server_response = (ServerResponse) object;
        
        debug("[%s] Dropped server response at %s: %s", to_string(), fsm.get_event_issued_string(state, event),
            server_response.to_string());
        
        return state;
    }
    
    // This handles commands that the user initiates before the session is in the AUTHENTICATED state
    private uint on_unauthenticated(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.UNAUTHENTICATED("Not authenticated with %s", to_string());
        
        return state;
    }
    
    private uint on_ignored_transition(uint state, uint event) {
        debug("[%s] Ignored transition: %s", to_string(), fsm.get_event_issued_string(state, event));
        
        return state;
    }
    
    //
    // command submission
    //
    
    private async StatusResponse command_transaction_async(Command cmd, Cancellable? cancellable)
        throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", imap_endpoint.to_string());
        
        yield cx.send_async(cmd, cancellable);
        
        // send_async() should've tagged the Command, otherwise the completion_pending will fail
        assert(cmd.tag.is_tagged());
        
        // If the command didn't complete (i.e. a CompletionStatusResponse didn't return from the
        // server) in the context of send_async(), wait for it now
        if (!seen_completion_responses.has_key(cmd.tag)) {
            waiting_for_completion.set(cmd.tag, new CommandCallback(command_transaction_async.callback));
            yield;
        }
        
        // it should be seen now; if not, it's because of disconnection cancelling all the outstanding
        // requests
        StatusResponse? completion_response;
        if (!seen_completion_responses.unset(cmd.tag, out completion_response)) {
            assert(cx == null);
            
            throw new ImapError.NOT_CONNECTED("Not connected to %s", imap_endpoint.to_string());
        }
        
        assert(completion_response != null);
        
        return completion_response;
    }
    
    //
    // network connection event handlers
    //
    
    private void on_network_connected() {
        debug("[%s] Connected to %s", to_string(), imap_endpoint.to_string());
        
        fsm.issue(Event.CONNECTED);
    }
    
    private void on_network_disconnected() {
        debug("[%s] Disconnected from %s", to_string(), imap_endpoint.to_string());
        
        fsm.issue(Event.DISCONNECTED);
    }
    
    private void on_network_sent_command(Command cmd) {
#if VERBOSE_SESSION
        debug("[%s] Sent command %s", to_string(), cmd.to_string());
#endif
        // resechedule keepalive
        schedule_keepalive();
    }
    
    private void on_network_send_error(Error err) {
        debug("[%s] Send error: %s", to_string(), err.message);
        
        fsm.issue(Event.SEND_ERROR, null, null, err);
    }
    
    private void on_received_status_response(StatusResponse status_response) {
        // reschedule keepalive (traffic seen on channel)
        schedule_keepalive();
        
        // If a CAPABILITIES ResponseCode, decode and update capabilities ...
        // some servers do this to prevent a second round-trip
        ResponseCode? response_code = status_response.response_code;
        if (response_code != null) {
            try {
                if (response_code.get_response_code_type().is_value(ResponseCodeType.CAPABILITY)) {
                    capabilities = response_code.get_capabilities(ref next_capabilities_revision);
                    debug("[%s] %s %s", to_string(), status_response.status.to_string(),
                        capabilities.to_string());
                    
                    capability(capabilities);
                }
            } catch (Error err) {
                debug("[%s] Unable to convert response code to capabilities: %s", to_string(),
                    err.message);
            }
        }
        
        // update state machine before notifying subscribers, who may turn around and query ClientSession
        if (status_response.is_completion) {
            fsm.issue(Event.RECV_COMPLETION, null, status_response, null);
            
            // Note that this signal could be called in the context of cx.send_async() that sent
            // this command to the server ... this mechanism (seen_completion_response and
            // waiting_for_completion) assures that in either case issue_command_async() returns
            // when the command is completed
            seen_completion_responses.set(status_response.tag, status_response);
            
            CommandCallback? cmd_cb;
            if (waiting_for_completion.unset(status_response.tag, out cmd_cb))
                Scheduler.on_idle(cmd_cb.callback);
        } else {
            fsm.issue(Event.RECV_STATUS, null, status_response, null);
        }
        
        status_response_received(status_response);
    }
    
    private void notify_received_data(ServerData server_data) throws ImapError {
        switch (server_data.server_data_type) {
            case ServerDataType.CAPABILITY:
                // update ClientSession capabilities before firing signal, so external signal
                // handlers that refer back to property aren't surprised
                capabilities = server_data.get_capabilities(ref next_capabilities_revision);
                debug("[%s] %s %s", to_string(), server_data.server_data_type.to_string(),
                    capabilities.to_string());
                
                capability(capabilities);
            break;
            
            case ServerDataType.EXISTS:
                exists(server_data.get_exists());
            break;
            
            case ServerDataType.EXPUNGE:
                expunge(server_data.get_expunge());
            break;
            
            case ServerDataType.FETCH:
                fetch(server_data.get_fetch());
            break;
            
            case ServerDataType.FLAGS:
                flags(server_data.get_flags());
            break;
            
            case ServerDataType.LIST:
            case ServerDataType.XLIST:
                list(server_data.get_list());
            break;
            
            case ServerDataType.RECENT:
                recent(server_data.get_recent());
            break;
            
            case ServerDataType.STATUS:
                status(server_data.get_status());
            break;
            
            case ServerDataType.SEARCH:
                search(server_data.get_search());
            break;
            
            // TODO: LSUB
            case ServerDataType.LSUB:
            default:
                // do nothing
                debug("[%s] Not notifying of unhandled server data: %s", to_string(),
                    server_data.to_string());
            break;
        }
        
        server_data_received(server_data);
    }
    
    private void on_received_server_data(ServerData server_data) {
        // reschedule keepalive (traffic seen on channel)
        schedule_keepalive();
        
        // send ServerData to upper layers for processing and storage
        try {
            notify_received_data(server_data);
        } catch (ImapError ierr) {
            debug("[%s] Failure notifying of server data: %s %s", to_string(), server_data.to_string(),
                ierr.message);
        }
    }
    
    private void on_received_bytes(size_t bytes) {
        // reschedule keepalive
        schedule_keepalive();
    }
    
    private void on_received_bad_response(RootParameters root, ImapError err) {
        debug("[%s] Received bad response %s: %s", to_string(), root.to_string(), err.message);
    }
    
    private void on_received_closed(ClientConnection cx) {
#if VERBOSE_SESSION
        // This currently doesn't generate any Events, but it does mean the connection has closed
        // due to EOS
        debug("[%s] Received closed", to_string());
#endif
    }
    
    private void on_network_receive_failure(Error err) {
        debug("[%s] Receive failed: %s", to_string(), err.message);
        
        fsm.issue(Event.RECV_ERROR, null, null, err);
    }
    
    public string to_string() {
        if (cx == null) {
            return "%s %s".printf(imap_endpoint.to_string(), fsm.get_state_string(fsm.get_state()));
        } else {
            return "%04X/%s %s".printf(cx.cx_id, imap_endpoint.to_string(),
                fsm.get_state_string(fsm.get_state()));
        }
    }
}

