/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSession {
    // 30 min keepalive required to maintain session
    public const uint MIN_KEEPALIVE_SEC = 30 * 60;
    
    // 5 minutes is more realistic, as underlying sockets will not necessarily report errors if
    // physical connection is lost
    public const uint RECOMMENDED_KEEPALIVE_SEC = 5 * 60;
    
    // A more aggressive keepalive will detect when a connection has died, thereby giving the client
    // a chance to reestablish a connection without long lags.
    public const uint AGGRESSIVE_KEEPALIVE_SEC = 30;
    
    // NOOP is only sent after this amount of time has passed since the last received
    // message on the connection dependant on connection state (selected/examined vs. authorized)
    public const uint DEFAULT_SELECTED_KEEPALIVE_SEC = AGGRESSIVE_KEEPALIVE_SEC;
    public const uint DEFAULT_UNSELECTED_KEEPALIVE_SEC = RECOMMENDED_KEEPALIVE_SEC;
    public const uint DEFAULT_SELECTED_WITH_IDLE_KEEPALIVE_SEC = AGGRESSIVE_KEEPALIVE_SEC;
    
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
        REMOTE_ERROR
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
    
    private enum State {
        // canonical IMAP session states
        DISCONNECTED,
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
        DISCONNECTING,
        
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
        
        COUNT;
    }
    
    private static string event_to_string(uint event) {
        return ((Event) event).to_string();
    }
    
    private static Geary.State.MachineDescriptor machine_desc = new Geary.State.MachineDescriptor(
        "Geary.Imap.ClientSession", State.DISCONNECTED, State.COUNT, Event.COUNT,
        state_to_string, event_to_string);
    
    /**
     * ClientSession tracks server extensions reported via the CAPABILITY server data response.
     * This comes automatically when logging in and can be fetched by the CAPABILITY command.
     * ClientSession stores the last seen list as a service for users and uses it internally
     * (specifically for IDLE support).  However, ClientSession will not automatically fetch
     * capabilities, only watch for them as they're reported.  Thus, it's recommended that users
     * of ClientSession issue a CapabilityCommand (if needed) before login.
     */
    private Capabilities capabilities { get; private set; default = new Capabilities(0); }
    
    private Endpoint imap_endpoint;
    private Geary.State.Machine fsm;
    private ClientConnection? cx = null;
    private string? current_mailbox = null;
    private bool current_mailbox_readonly = false;
    private Gee.HashMap<Tag, CompletionStatusResponse> seen_completion_responses = new Gee.HashMap<
        Tag, CompletionStatusResponse>(Hashable.hash_func, Equalable.equal_func);
    private Gee.HashMap<Tag, CommandCallback> waiting_for_completion = new Gee.HashMap<
        Tag, CommandCallback>(Hashable.hash_func, Equalable.equal_func);
    private int next_capabilities_revision = 1;
    private uint keepalive_id = 0;
    private uint selected_keepalive_secs = 0;
    private uint unselected_keepalive_secs = 0;
    private uint selected_with_idle_keepalive_secs = 0;
    private bool allow_idle = true;
    private Command? state_change_cmd = null;
    
    //
    // Connection state changes
    //
    
    public virtual signal void connected() {
    }
    
    public virtual signal void session_denied(string? reason) {
    }
    
    public virtual signal void authorized() {
    }
    
    public virtual signal void logged_out() {
    }
    
    public virtual signal void login_failed() {
    }
    
    public virtual signal void disconnected(DisconnectReason reason) {
    }
    
    //
    // ServerData (always untagged)
    //
    
    /**
     * Fired *before* the specific ServerData signals (i.e. "capability", "exists", "expunge", etc.)
     */
    public virtual signal void server_data_received(ServerData server_data) {
    }
    
    public virtual signal void capability(Capabilities capabilities) {
    }
    
    public virtual signal void exists(int count) {
    }
    
    public virtual signal void expunge(MessageNumber msg_num) {
    }
    
    public virtual signal void fetch(FetchedData fetched_data) {
    }
    
    public virtual signal void flags(MailboxAttributes mailbox_attrs) {
    }
    
    public virtual signal void list(MailboxInformation mailbox_info) {
    }
    
    // TODO: LSUB results
    
    public virtual signal void recent(int count) {
    }
    
    // TODO: SEARCH results
    
    public virtual signal void status(StatusData status_data) {
    }
    
    /**
     * If the mailbox name is null it indicates the type of state change that has occurred
     * (authorized -> selected/examined or vice-versa).  If new_name is null readonly should be
     * ignored.
     */
    public virtual signal void current_mailbox_changed(string? old_name, string? new_name, bool readonly) {
    }
    
    public ClientSession(Endpoint imap_endpoint) {
        this.imap_endpoint = imap_endpoint;
        
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.DISCONNECTED, Event.CONNECT, on_connect),
            new Geary.State.Mapping(State.DISCONNECTED, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.DISCONNECT, Geary.State.nop),
            
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
            
            new Geary.State.Mapping(State.NOAUTH, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGIN, on_login),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.NOAUTH, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.NOAUTH, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_COMPLETION, on_recv_completion),
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
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_COMPLETION, on_recv_completion),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.SELECTING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.SELECTING, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTING, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTING, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_STATUS, on_selecting_recv_status),
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
            new Geary.State.Mapping(State.SELECTED, Event.RECV_COMPLETION, on_recv_completion),
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
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_COMPLETION, on_logging_out_recv_completion),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_ERROR, on_disconnected),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_ERROR, on_disconnected),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.DISCONNECTING, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.DISCONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTING, Event.DISCONNECTED, on_disconnected),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SEND_ERROR, on_disconnected),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_ERROR, on_disconnected),
            
            new Geary.State.Mapping(State.BROKEN, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECTED, Geary.State.nop),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_COMPLETION, on_dropped_response)
        };
        
        fsm = new Geary.State.Machine(machine_desc, mappings, on_ignored_transition);
        fsm.set_logging(true);
    }
    
    ~ClientSession() {
        switch (fsm.get_state()) {
            case State.DISCONNECTED:
            case State.BROKEN:
                // no problem-o
            break;
            
            default:
                error("[%s] ClientSession ref dropped while still active", to_string());
        }
        
        debug("DTOR: ClientSession");
    }
    
    public string? get_current_mailbox() {
        return current_mailbox;
    }
    
    public bool is_current_mailbox_readonly() {
        return current_mailbox_readonly;
    }
    
    public Context get_context(out string? current_mailbox) {
        current_mailbox = null;
        
        switch (fsm.get_state()) {
            case State.DISCONNECTED:
            case State.LOGGED_OUT:
            case State.LOGGING_OUT:
            case State.DISCONNECTING:
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
    
    //
    // connect
    //
    
    public async void connect_async(Cancellable? cancellable = null) throws Error {
        MachineParams params = new MachineParams(null);
        fsm.issue(Event.CONNECT, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        // ClientConnection should exist at this point
        assert(cx != null);
        
        yield cx.connect_async(cancellable);
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
        cx.received_completion_status_response.connect(on_received_completion_status_response);
        cx.received_server_data.connect(on_received_server_data);
        cx.received_bytes.connect(on_received_bytes);
        cx.received_bad_response.connect(on_received_bad_response);
        cx.recv_closed.connect(on_received_closed);
        cx.receive_failure.connect(on_network_receive_failure);
        cx.deserialize_failure.connect(on_network_receive_failure);
        
        // only use IDLE when in SELECTED or EXAMINED state
        cx.set_idle_when_quiet(false);
        
        result.proceed = true;
        
        return State.CONNECTING;
    }
    
    // this is used internally to tear-down the ClientConnection object and unhook it from
    // ClientSession
    private void drop_connection() {
        unschedule_keepalive();
        
        if (cx == null)
            return;
        
        cx.connected.disconnect(on_network_connected);
        cx.disconnected.disconnect(on_network_disconnected);
        cx.sent_command.disconnect(on_network_sent_command);
        cx.send_failure.disconnect(on_network_send_error);
        cx.received_status_response.disconnect(on_received_status_response);
        cx.received_completion_status_response.disconnect(on_received_completion_status_response);
        cx.received_server_data.disconnect(on_received_server_data);
        cx.received_bytes.disconnect(on_received_bytes);
        cx.received_bad_response.disconnect(on_received_bad_response);
        cx.recv_closed.disconnect(on_received_closed);
        cx.receive_failure.disconnect(on_network_receive_failure);
        cx.deserialize_failure.disconnect(on_network_receive_failure);
        
        cx = null;
        
        // if there are any outstanding commands waiting for responses, wake them up now
        if (waiting_for_completion.size > 0) {
            debug("[%s] Cancelling %d pending commands", to_string(), waiting_for_completion.size);
            foreach (CommandCallback cmd_cb in waiting_for_completion.values)
                Scheduler.on_idle(cmd_cb.callback);
            
            waiting_for_completion.clear();
        }
    }
    
    private void on_connected(uint state, uint event) {
        debug("[%s] Connected", to_string());
        
        fsm.do_post_transition(() => { connected(); });
        
        // stay in current state -- wait for initial status response to move into NOAUTH or LOGGED OUT
        return state;
    }
    
    private void on_connecting_recv_status(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        if (status_response.status == Status.OK)
            return State.NOAUTH;
        
        debug("[%s] Connect denied: %s", to_string(), status_response.to_string());
        
        fsm.do_post_transition(() => { session_denied(status_response.text); });
        
        return State.LOGGED_OUT;
    }
    
    //
    // login
    //
    
    /**
     * Performs the LOGIN command using the supplied credentials.  See initiate_session_async() for
     * a more full-featured version of login_async().
     */
    public async CompletionStatusResponse login_async(Geary.Credentials credentials, Cancellable? cancellable = null)
        throws Error {
        LoginCommand cmd = new LoginCommand(credentials.user, credentials.pass);
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.LOGIN, null, param);
        
        if (params.err != null)
            throw params.err;
        
        assert(result.proceed);
        
        return yield command_transaction_async(cmd, cancellable);
    }
    
    /**
     * Prepares the connection and performs a login using the supplied credentials.  Preparing the
     * connnection includes attempting compression and using STARTTLS if necessary.
     */
    public async void initiate_session_async(Geary.Credentials credentials, Cancellable? cancellable = null)
        throws Error {
        // If no capabilities available, get them now
        if (capabilities.is_empty())
            yield send_command_async(new CapabilityCommand());
        
        Imap.Capabilities caps = capabilities;
        
        debug("[%s] use_starttls=%s is_ssl=%s starttls=%s", to_string(), imap_endpoint.use_starttls.to_string(),
            imap_endpoint.is_ssl.to_string(), caps.has_capability(Capabilities.STARTTLS).to_string());
        switch (imap_endpoint.attempt_starttls(caps.has_capability(Capabilities.STARTTLS))) {
            case Endpoint.AttemptStarttls.YES:
                debug("[%s] Attempting STARTTLS...", to_string());
                CompletionStatusResponse resp;
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
                    debug("[%s} STARTTLS refused: %s", to_string(), resp.status_response.to_string());
                    
                    // throw an exception and fail rather than send credentials under suspect
                    // conditions
                    throw new ImapError.NOT_SUPPORTED("STARTTLS refused by %s: %s", to_string(),
                        resp.status_response.to_string());
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
        CompletionStatusResponse login_resp = yield login_async(credentials, cancellable);
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
            CompletionStatusResponse resp = yield send_command_async(
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
        state_change_cmd = params.cmd;
        
        params.proceed = true;
         
        return State.AUTHORIZING;
    }
    
    private uint on_logging_in(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.err = new ImapError.FAILED("Already logging in to %s", to_string());
        
        return state;
    }
    
    private uint on_login_recv_completion(uint state, uint event, void *user, Object? object) {
        CompletionStatusResponse completion_response = (CompletionStatusResponse) object;
        
        // only interested in LoginCommand returning
        assert(state_change_cmd != null);
        if (!completion_response.tag.equals(state_change_cmd.tag))
            return on_recv_completion(state, event, user, object);
        
        debug("[%s] on_login_recv_completion: %s", to_string(), completion_response.to_string());
        
        // release for next state change command
        state_change_cmd = null;
        
        // Remember: only you can prevent firing signals inside state transition handlers
        switch (completion_response.status) {
            case Status.OK:
                fsm.do_post_transition(() => { authorized(); });
                
                return State.AUTHORIZED;
            
            default:
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
        CompletionStatusResponse response;
        try {
            response = send_command_async.end(result);
            Logging.debug(Logging.Flag.PERIODIC, "[%s] Keepalive result: %s", to_string(),
                response.to_string());
        } catch (Error err) {
            debug("[%s] Keepalive error: %s", to_full_string(), err.message);
            
            return;
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
        return get_capabilities().has_capability(Capabilities.IDLE);
    }
    
    //
    // send commands
    //
    
    public async CompletionStatusResponse send_command_async(Command cmd, Cancellable? cancellable = null) 
        throws Error {
        // look for special commands that we wish to handle directly, as they affect the state
        // machine
        //
        // TODO: Convert commands into proper calls to avoid throwing an exception
        if (cmd.has_name(LoginCommand.NAME) || cmd.has_name(LogoutCommand.NAME)
            || cmd.has_name(SelectCommand.NAME) || cmd.has_name(ExamineCommand.NAME)
            || cmd.has_name(CloseCommand.NAME)) {
            throw new ImapError.NOT_SUPPORTED("Use direct calls rather than commands for %s", cmd.name);
        }
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.SEND_CMD, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        return yield command_transaction_async(cmd, cancellable);
    }
    
    private uint on_send_command(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        debug("[%s] command: %s", to_string(), params.cmd.to_string());
        
        params.proceed = true;
        
        return state;
    }
    
    private uint on_recv_status(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        debug("[%s] status response: %s", to_string(), status_response.to_string());
        
        switch (status_response.status) {
            case Status.BYE:
                fsm.do_post_transition(() => { disconnected(DisconnectReason.REMOTE_CLOSE); });
                
                return State.DISCONNECTED;
        }
        
        return state;
    }
    
    private uint on_recv_completion(uint state, uint event, void *user, Object? object) {
        CompletionStatusResponse completion_response = (CompletionStatusResponse) object;
        
        debug("[%s] completion response: %s", to_string(), completion_response.to_string());
        
        return state;
    }
    
    //
    // select/examine
    //
    
    public async CompletionStatusResponse select_async(string mailbox, Cancellable? cancellable = null) 
        throws Error {
        return yield select_examine_async(mailbox, true, cancellable);
    }
    
    public async CompletionStatusResponse examine_async(string mailbox, Cancellable? cancellable = null)
        throws Error {
        return yield select_examine_async(mailbox, false, cancellable);
    }
    
    public async CompletionStatusResponse select_examine_async(string mailbox, bool is_select,
        Cancellable? cancellable) throws Error {
        string? old_mailbox = current_mailbox;
        
        Command cmd = is_select ? new SelectCommand(mailbox) : new ExamineCommand(mailbox);
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.SELECT, null, params);
        
        if (params.err != null)
            throw params.err;
        
        assert(params.proceed);
        
        CompletionStatusResponse completion_response = yield command_transaction_async(cmd,
            cancellable);
        
        // TODO: change this state inside state machine
        if (completion_response.status == Status.OK) {
            current_mailbox = mailbox;
            current_mailbox_readonly = !is_select;
        }
        
        // TODO: We may want to move this signal into the async completion handler rather than
        // fire it here because async callbacks are scheduled on the event loop and their order
        // of execution is not guaranteed
        //
        // TODO: fire this post-transition
        assert(current_mailbox != null);
        current_mailbox_changed(old_mailbox, current_mailbox, current_mailbox_readonly);
        
        return completion_response;
    }
    
    private uint on_select(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(params.cmd != null);
        state_change_cmd = params.cmd;
        
        // Allow IDLE *before* issuing SELECT/EXAMINE because there's no guarantee another command
        // will be issued any time soon, which is necessary for the IDLE command to be tacked on
        // to the end of it.  In other words, telling ClientConnection to go into IDLE after the
        // SELECT/EXAMINE command is too late unless another command is sent (set_idle_when_quiet()
        // performs no I/O).
        cx.set_idle_when_quiet(allow_idle && supports_idle());
        
        params.proceed = true;
        
        return State.SELECTING;
    }
    
    private uint on_not_selected(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.err = new ImapError.INVALID("Can't close mailbox, not selected");
        
        return state;
    }
    
    private uint on_selecting_recv_completion(uint state, uint event, void *user, Object? object) {
        CompletionStatusResponse completion_response = (CompletionStatusResponse) object;
        
        assert(state_change_cmd != null);
        if (!completion_response.tag.equals(state_change_cmd.tag))
            return on_recv_completion(state, event, user, object);
        
        switch (completion_response.status) {
            case Status.OK:
                // mailbox is SELECTED/EXAMINED
                return State.SELECTED;
            
            default:
                // turn off IDLE, not entering SELECTED/EXAMINED state
                cx.set_idle_when_quiet(false);
                
                return State.AUTHORIZED;
        }
    }
    
    //
    // close mailbox
    //
    
    public async CompletionStatusResponse close_mailbox_async(Cancellable? cancellable = null) throws Error {
        string? old_mailbox = current_mailbox;
        
        CloseCommand cmd = new CloseCommand();
        
        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.CLOSE_MAILBOX, null, params);
        
        if (params.err != null)
            throw params.err;
        
        CompletionStatusResponse completion_response = yield command_transaction_async(cmd, cancellable);
        
        // possible for a close_mailbox to occur when already closed, but don't fire signal in
        // that case
        //
        // TODO: See note in select_examine_async() for why it might be better to fire this signal
        // in the async completion handler rather than here
        //
        // TODO: Do this inside FSM
        if (completion_response.status == Status.OK && old_mailbox != null)
            current_mailbox_changed(old_mailbox, null, false);
        
        return completion_response;
    }
    
    private uint on_close_mailbox(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(params.cmd is CloseCommand);
        state_change_cmd = params.cmd;
        
        // returning to AUTHORIZED state, turn off IDLE
        cx.set_idle_when_quiet(false);
        
        params.proceed = true;
        
        return State.CLOSING_MAILBOX;
    }
    
    private uint on_closing_recv_completion(uint state, uint event, void *user, Object? object) {
        CompletionStatusResponse completion_response = (CompletionStatusResponse) object;
        
        assert(state_change_cmd != null);
        if (!completion_response.tag.equals(state_change_cmd.tag))
            return on_recv_completion(state, event, user, object);
        
        state_change_cmd = null;
        
        switch (completion_response.status) {
            case Status.OK:
                current_mailbox = null;
                
                return State.AUTHORIZED;
            
            default:
                return State.SELECTED;
        }
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
        
        if(params.proceed);
            yield command_transaction_async(cmd, cancellable);
    }
    
    private uint on_logout(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        assert(params.cmd != null);
        state_change_cmd = params.cmd;
        
        params.proceed = true;
        
        return State.LOGGING_OUT;
    }
    
    private uint on_logging_out_recv_completion(uint state, uint event, void *user, Object? object) {
        CompletionStatusResponse completion_response = (CompletionStatusResponse) object;
        
        assert(state_change_cmd != null);
        if (!completion_response.tag.equals(state_change_cmd.tag))
            return on_recv_completion(state, event, user, object);
        
        state_change_cmd = null;
        
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
        
        if (result.proceed)
            yield cx.disconnect_async(cancellable);
    }
    
    private uint on_disconnect(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;
        
        params.proceed = true;
        
        return State.DISCONNECTING;
    }
    
    private uint on_disconnected(uint state, uint event) {
        // don't do inside signal handler -- although today drop_connection() doesn't fire signals or call
        // callbacks, it could in the future
        fsm.do_post_transition(() => {
            drop_connection();
            disconnected(DisconnectReason.LOCAL_CLOSE);
        });
        
        // although we could go to the DISCONNECTED state, that implies the object can be reused ...
        // while possible, that requires all state (not just the FSM) be reset at this point, and
        // it just seems simpler and less buggy to require the user to discard this object and
        // instantiate a new one
        
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
        
        debug("[%s] Connecting send error, dropping client connection: %s", to_full_string(), err.message);
        
        fsm.do_post_transition(() => { drop_connection(); });
        
        return State.BROKEN;
    }
    
    private uint on_send_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        
        if (err is IOError.CANCELLED)
            return state;
        
        debug("[%s] Send error, disconnecting: %s", to_full_string(), err.message);
        
        cx.disconnect_async.begin(null, on_fire_send_error_signal);
        
        return State.BROKEN;
    }
    
    private void on_fire_send_error_signal(Object? object, AsyncResult result) {
        dispatch_send_recv_results(DisconnectReason.LOCAL_ERROR, result);
    }
    
    private uint on_recv_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        debug("[%s] Receive error, disconnecting: %s", to_full_string(), err.message);
        
        cx.disconnect_async.begin(null, on_fire_recv_error_signal);
        
        return State.BROKEN;
    }
    
    private void on_fire_recv_error_signal(Object? object, AsyncResult result) {
        dispatch_send_recv_results(DisconnectReason.REMOTE_ERROR, result);
    }
    
    private void dispatch_send_recv_results(DisconnectReason reason, AsyncResult result) {
        debug("[%s] Disconnected due to %s", to_full_string(), reason.to_string());
        
        try {
            cx.disconnect_async.end(result);
        } catch (Error err) {
            debug("[%s] Send/recv disconnect failed: %s", to_full_string(), err.message);
        }
        
        drop_connection();
        
        disconnected(reason);
    }
    
    // This handles the situation where the user submits a command before the connection has been
    // established
    private uint on_early_command(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.NOT_CONNECTED("Not connected to %s", to_string());
        
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
        params.err = new ImapError.FAILED("Already connected or connecting to %s", to_string());
        
        return state;
    }
    
    private uint on_already_logged_in(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        MachineParams params = (MachineParams) object;
        params.err = new ImapError.FAILED("Already logged in to %s", to_string());
        
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
        debug("Ignored transition: %s", fsm.get_event_issued_string(state, event));
        
        return state;
    }
    
    //
    // command submission
    //
    
    private async CompletionStatusResponse command_transaction_async(Command cmd, Cancellable? cancellable)
        throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", imap_endpoint.to_string());
        
        yield cx.send_async(cmd, cancellable);
        
        // send_async() should've tagged the Command, otherwise the completion_pending will fail
        assert(cmd.tag.is_tagged());
        
        // If the command didn't complete (i.e. a CompletionStatusResponse didn't return from the
        // server) in the context of send_async(), wait for it now
        if (!seen_completion_responses.has_key(cmd.tag)) {
            debug("[%s] Waiting for completion status response %s...", to_string(), cmd.to_string());
            waiting_for_completion.set(cmd.tag, new CommandCallback(issue_command_async.callback));
            yield;
        }
        
        // it should be seen now; if not, it's because of disconnection cancelling all the outstanding
        // requests
        CompletionStatusResponse? completion_response;
        if (!seen_completion_response.remove(cmd.tag, out completion_response)) {
            assert(cx == null);
            
            throw new ImapError.NOT_CONNECTED("Not connected to %s", imap_endpoint.to_string());
        }
        
        assert(completion_response != null);
        
        if (completion_response.status != Status.OK)
            throw new ImapError.FAILED("Command %s failed: %s", cmd.name, completion_response.to_string());
        
        return completion_response;
    }
    
    //
    // network connection event handlers
    //
    
    private void on_network_connected() {
        debug("[%s] Connected to %s", to_full_string(), imap_endpoint.to_string());
        
        fsm.issue(Event.CONNECTED);
    }
    
    private void on_network_disconnected() {
        debug("[%s] Disconnected from %s", to_full_string(), imap_endpoint.to_string());
        
        fsm.issue(Event.DISCONNECTED);
    }
    
    private void on_network_sent_command(Command cmd) {
#if VERBOSE_SESSION
        debug("[%s] Sent command %s", to_full_string(), cmd.to_string());
#endif
        // resechedule keepalive
        schedule_keepalive();
    }
    
    private void on_network_send_error(Error err) {
        debug("[%s] Send error: %s", to_full_string(), err.message);
        fsm.issue(Event.SEND_ERROR, null, null, err);
    }
    
    private void on_received_status_response(StatusResponse status_response) {
        // reschedule keepalive (traffic seen on channel)
        schedule_keepalive();
        
        fsm.issue(Event.RECV_STATUS, null, status_response, null);
    }
    
    private void on_received_completion_status_response(CompletionStatusResponse completion_status_response) {
        // reschedule keepalive (traffic seen on channel)
        schedule_keepalive();
        
        // issue event change before looking for waiting command issuers
        fsm.issue(Event.RECV_COMPLETION, null, completion_status_response, null);
        
        // Note that this signal could be called in the context of cx.send_async() that sent
        // this command to the server ... this mechanism (seen_completion_response and
        // waiting_for_completion) assures that in either case issue_command_async() returns
        // when the command is completed
        seen_completion_response.set(completion_status_response.tag, completion_status_response);
        
        CommandCallback? cmd_cb;
        if (waiting_for_completion.remove(completion_status_response.tag, out cmd_cb))
            Idle.schedule(cmd_cb.callback);
    }
    
    private void notify(ServerData server_data) throws ImapError {
        switch (server_data.server_data_type) {
            case ServerDataType.CAPABILITY:
                // update ClientSession capabilities before firing signal, so external signal
                // handlers that refer back to property aren't surprised
                capabilities = server_data.get_capabilities(ref next_capabilities_revision);
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
                list(server_data.get_list());
            break;
            
            case ServerDataType.RECENT:
                recent(server_data.get_recent());
            break;
            
            case ServerDataType.STATUS:
                status(server_data.get_status());
            break;
            
            // TODO: LSUB and SEARCH
            case ServerDataType.LSUB:
            case ServerDataType.SEARCH:
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
            notify(server_data);
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
        debug("[%s] Received bad response %s: %s", to_full_string(), root.to_string(), err.message);
    }
    
    private void on_received_closed(ClientConnection cx) {
#if VERBOSE_SESSION
        // This currently doesn't generate any Events, but it does mean the connection has closed
        // due to EOS
        debug("[%s] Received closed", to_full_string());
#endif
    }
    
    private void on_network_receive_failure(Error err) {
        debug("[%s] Receive failed: %s", to_full_string(), err.message);
        
        fsm.issue(Event.RECV_ERROR, null, null, err);
    }
    
    public string to_string() {
        return "ClientSession:%s".printf((cx == null) ? imap_endpoint.to_string() : cx.to_string());
    }
    
    public string to_full_string() {
        return "%s [%s]".printf(to_string(), fsm.get_state_string(fsm.get_state()));
    }
}

