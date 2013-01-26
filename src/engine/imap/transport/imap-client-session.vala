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
    
    // Need this because delegates with targets cannot be stored in ADTs.
    private class CommandCallback {
        public unowned SourceFunc callback;
        
        public CommandCallback(SourceFunc callback) {
            this.callback = callback;
        }
    }
    
    private class AsyncCommandResponse {
        public CompletionStatusResponse? completion_response { get; private set; }
        public Object? user { get; private set; }
        public Error? err { get; private set; }
        
        public AsyncCommandResponse(CompletionStatusResponse? completion_response, Object? user,
            Error? err) {
            this.completion_response = completion_response;
            this.user = user;
            this.err = err;
        }
    }
    
    // Many of the async commands go through the FSM, and this is used to pass state around until
    // the multiple transitions are completed
    private class AsyncParams : Object {
        public Cancellable? cancellable;
        public unowned SourceFunc cb;
        public CompletionStatusResponse? completion_response = null;
        public Error? err = null;
        public bool do_yield = false;
        
        public AsyncParams(Cancellable? cancellable, SourceFunc cb) {
            this.cancellable = cancellable;
            this.cb = cb;
        }
    }
    
    private class LoginParams : AsyncParams {
        public string user;
        public string pass;
        
        public LoginParams(string user, string pass, Cancellable? cancellable, SourceFunc cb) {
            base (cancellable, cb);
            
            this.user = user;
            this.pass = pass;
        }
    }
    
    private class SelectParams : AsyncParams {
        public string mailbox;
        public bool is_select;
        
        public SelectParams(string mailbox, bool is_select, Cancellable? cancellable, SourceFunc cb) {
            base (cancellable, cb);
            
            this.mailbox = mailbox;
            this.is_select = is_select;
        }
    }
    
    private class SendCommandParams : AsyncParams {
        public Command cmd;
        
        public SendCommandParams(Command cmd, Cancellable? cancellable, SourceFunc cb) {
            base (cancellable, cb);
            
            this.cmd = cmd;
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
        // user-initated events
        CONNECT,
        LOGIN,
        SEND_CMD,
        SELECT,
        CLOSE_MAILBOX,
        LOGOUT,
        DISCONNECT,
        
        // server responses
        RECV_STATUS,
        RECV_COMPLETION,
        RECV_DATA,
        DISCONNECTED,
        
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
    private ServerDataNotifier notifier;
    private Geary.State.Machine fsm;
    private ImapError not_connected_err;
    private ClientConnection? cx = null;
    private string? current_mailbox = null;
    private bool current_mailbox_readonly = false;
    private Gee.HashMap<Tag, CommandCallback> tag_cb = new Gee.HashMap<Tag, CommandCallback>(
        Hashable.hash_func, Equalable.equal_func);
    private int next_capabilities_revision = 1;
    private uint keepalive_id = 0;
    private uint selected_keepalive_secs = 0;
    private uint unselected_keepalive_secs = 0;
    private uint selected_with_idle_keepalive_secs = 0;
    private bool allow_idle = true;
    
    // state used only during connect and disconnect
    private AsyncParams? connect_params = null;
    private AsyncParams? disconnect_params = null;
    
    public virtual signal void connected() {
    }
    
    public virtual signal void authorized() {
    }
    
    public virtual signal void logged_out() {
    }
    
    public virtual signal void login_failed() {
    }
    
    public virtual signal void disconnected(DisconnectReason reason) {
    }
    
    /**
     * If the mailbox name is null it indicates the type of state change that has occurred
     * (authorized -> selected/examined or vice-versa).  If new_name is null readonly should be
     * ignored.
     */
    public virtual signal void current_mailbox_changed(string? old_name, string? new_name, bool readonly) {
    }
    
    public ClientSession(Endpoint imap_endpoint, ServerDataNotifier notifier) {
        this.imap_endpoint = imap_endpoint;
        this.notifier = notifier;
        allow_idle = true;
        
        not_connected_err = new ImapError.NOT_CONNECTED("Not connected to %s", imap_endpoint.to_string());
        
        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.DISCONNECTED, Event.CONNECT, on_connect),
            new Geary.State.Mapping(State.DISCONNECTED, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.DISCONNECTED, Event.DISCONNECT, Geary.State.nop),
            
            new Geary.State.Mapping(State.CONNECTING, Event.CONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.CONNECTING, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_STATUS, on_connecting_response_status),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.NOAUTH, Event.LOGIN, on_login),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.NOAUTH, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.NOAUTH, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_STATUS, on_dropped_response,
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_COMPLETION, on_command_completed,
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_DATA, Geary.State.nop,
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGIN, Geary.State.nop),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_STATUS, on_dropped_response,
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_COMPLETION, on_login_completed,
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_DATA, Geary.State.nop,
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_STATUS, on_dropped_response,
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_COMPLETION, on_recv_completion,
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_DATA, Geary.State.nop,
            new Geary.State.Mapping(State.AUTHORIZED, Event.CLOSE_MAILBOX, Geary.State.nop),
            new Geary.State.Mapping(State.AUTHORIZED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_ERROR, on_recv_error),
            
            // TODO: technically, if the user selects while selecting, we should handle this
            // in some fashion
            new Geary.State.Mapping(State.SELECTING, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTING, Event.SELECT, Geary.State.nop),
            new Geary.State.Mapping(State.SELECTING, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_STATUS, on_selecting_status_response),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_COMPLETION, on_selecting_completion_response),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.SELECTING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTING, Event.SELECTED, on_selected),
            new Geary.State.Mapping(State.SELECTING, Event.SELECT_FAILED, on_select_failed),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.SELECTED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_STATUS, Geary.State.nop),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_COMPLETION, Geary.State.nop),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_DATA, Geary.State.nop),
            new Geary.State.Mapping(State.SELECTED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTED, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_STATUS, on_closing_status_response),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_COMPLETION, on_closing_completion_response),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CLOSE_MAILBOX, Geary.State.nop),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CLOSED_MAILBOX, on_closed_mailbox),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CLOSE_MAILBOX_FAILED, on_close_mailbox_failed),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.LOGGING_OUT, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.LOGOUT, Geary.State.nop),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.LOGOUT_SUCCESS, on_logged_out),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.LOGOUT_FAILED, Geary.State.nop),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.RECV_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.LOGGING_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.DISCONNECTING, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.DISCONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTING, Event.DISCONNECTED, on_disconnected),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SEND_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_ERROR, Geary.State.nop),
            
            new Geary.State.Mapping(State.BROKEN, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.BROKEN, Event.RECV_DATA, on_dropped_response),
            new Geary.State.Mapping(State.BROKEN, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECTED, Geary.State.nop)
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
        AsyncParams params = new AsyncParams(cancellable, connect_async.callback);
        fsm.issue(Event.CONNECT, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
    }
    
    private uint on_connect(uint state, uint event, void *user, Object? object) {
        assert(connect_params == null);
        connect_params = (AsyncParams) object;
        
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
        
        cx.connect_async.begin(connect_params.cancellable, on_connect_completed);
        
        connect_params.do_yield = true;
        
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
        if (tag_cb.size > 0) {
            debug("[%s] Cancelling %d pending commands", to_string(), tag_cb.size);
            foreach (Tag tag in tag_cb.keys)
                Scheduler.on_idle(tag_cb.get(tag).callback);
            
            tag_cb.clear();
        }
    }
    
    private void on_connect_completed(Object? source, AsyncResult result) {
        assert(connect_params != null);
        
        try {
            cx.connect_async.end(result);
        } catch (Error err) {
            fsm.issue(Event.SEND_ERROR, null, null, err);
            connect_params.err = err;
        }
        
        Scheduler.on_idle(connect_params.cb);
        
        // drop internal reference, caller is holding on to it
        connect_params = null;
    }
    
    private void on_connecting_response_status(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;
        
        if (status_response.status == Status.OK)
            return State.NOAUTH;
        
        debug("[%s] Connect denied: %s", to_string(), status_response.to_string());
        
        return State.BROKEN;
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
        LoginParams params = new LoginParams(credentials.user, credentials.pass ?? "", cancellable,
            login_async.callback);
        fsm.issue(Event.LOGIN, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
        
        // No Error means a response had better be available
        assert(params.completion_response != null);
        
        return params.completion_response;
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
                CommandResponse resp;
                try {
                    resp = yield send_command_async(new StarttlsCommand());
                } catch (Error err) {
                    debug("Error attempting STARTTLS command on %s: %s", to_string(), err.message);
                    
                    throw err;
                }
                
                if (resp.status_response.status == Status.OK) {
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
        LoginParams params = (LoginParams) object;
        
        issue_command_async.begin(new LoginCommand(params.user, params.pass), params,
            params.cancellable, generic_issue_command_completion);
        
        params.do_yield = true;
        
        return State.AUTHORIZING;
    }
    
    private uint on_login_completed(uint state, uint event, void *user, Object? object) {
        CompletionStatusResponse completion_response = (CompletionStatusResponse) object;
        
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
        CommandResponse response;
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
        
        SendCommandParams params = new SendCommandParams(cmd, cancellable, send_command_async.callback);
        fsm.issue(Event.SEND_CMD, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
        
        return params.completion_response;
    }
    
    private uint on_send_command(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        SendCommandParams params = (SendCommandParams) object;
        
        issue_command_async.begin(params.cmd, params, params.cancellable, on_send_command_completed);
        
        params.do_yield = true;
        
        return state;
    }
    
    private void on_send_command_completed(Object? source, AsyncResult result) {
        generic_issue_command_completed(result, Event.SENT_COMMAND, Event.SEND_COMMAND_FAILED);
    }
    
    //
    // select/examine
    //
    
    public async SelectExamineResults select_async(string mailbox, Cancellable? cancellable = null) 
        throws Error {
        return yield select_examine_async(mailbox, true, cancellable);
    }
    
    public async SelectExamineResults examine_async(string mailbox, Cancellable? cancellable = null)
        throws Error {
        return yield select_examine_async(mailbox, false, cancellable);
    }
    
    public async SelectExamineResults select_examine_async(string mailbox, bool is_select,
        Cancellable? cancellable) throws Error {
        string? old_mailbox = current_mailbox;
        
        SelectParams params = new SelectParams(mailbox, is_select, cancellable,
            select_examine_async.callback);
        fsm.issue(Event.SELECT, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
        
        // TODO: We may want to move this signal into the async completion handler rather than
        // fire it here because async callbacks are scheduled on the event loop and their order
        // of execution is not guaranteed
        assert(current_mailbox != null);
        current_mailbox_changed(old_mailbox, current_mailbox, current_mailbox_readonly);
        
        return SelectExamineResults.decode(params.cmd_response);
    }
    
    private uint on_select(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        SelectParams params = (SelectParams) object;
        
        if (current_mailbox != null && current_mailbox == params.mailbox)
            return state;
        
        // TODO: Currently don't handle situation where one mailbox is selected and another is
        // asked for without closing
        assert(current_mailbox == null);
        
        // Allow IDLE *before* issuing SELECT/EXAMINE because there's no guarantee another command
        // will be issued any time soon, which is necessary for the IDLE command to be tacked on
        // to the end of it.  In other words, telling ClientConnection to go into IDLE after the
        // SELECT/EXAMINE command is too late unless another command is sent (set_idle_when_quiet()
        // performs no I/O).
        cx.set_idle_when_quiet(allow_idle && supports_idle());
        
        Command cmd = params.is_select ? new SelectCommand(params.mailbox) : new ExamineCommand(params.mailbox);
        issue_command_async.begin(cmd, params, params.cancellable, on_select_completed);
        
        params.do_yield = true;
        
        return State.SELECTING;
    }
    
    private void on_select_completed(Object? source, AsyncResult result) {
        generic_issue_command_completed(result, Event.SELECTED, Event.SELECT_FAILED);
    }
    
    private uint on_selected(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        SelectParams params = (SelectParams) object;
        
        assert(current_mailbox == null);
        current_mailbox = params.mailbox;
        current_mailbox_readonly = !params.is_select;
        
        return State.SELECTED;
    }
    
    private uint on_select_failed(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        // turn off idle, not entering SELECTED/EXAMINED state
        cx.set_idle_when_quiet(false);
        
        SelectParams params = (SelectParams) object;
        
        params.err = new ImapError.COMMAND_FAILED("Unable to select mailbox \"%s\": %s",
            params.mailbox, params.cmd_response.to_string());
        
        return State.AUTHORIZED;
    }
    
    //
    // close mailbox
    //
    
    public async void close_mailbox_async(Cancellable? cancellable = null) throws Error {
        string? old_mailbox = current_mailbox;
        
        AsyncParams params = new AsyncParams(cancellable, close_mailbox_async.callback);
        fsm.issue(Event.CLOSE_MAILBOX, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
        
        assert(current_mailbox == null);
        
        // possible for a close_mailbox to occur when already closed, but don't fire signal in
        // that case
        //
        // TODO: See note in select_examine_async() for why it might be better to fire this signal
        // in the async completion handler rather than here
        if (old_mailbox != null)
            current_mailbox_changed(old_mailbox, null, false);
    }
    
    private uint on_close_mailbox(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        // returning to AUTHORIZED state, turn off IDLE
        cx.set_idle_when_quiet(false);
        
        AsyncParams params = (AsyncParams) object;
        
        issue_command_async.begin(new CloseCommand(), params, params.cancellable,
            on_close_mailbox_completed);
        
        params.do_yield = true;
        
        return State.CLOSING_MAILBOX;
    }
    
    private void on_close_mailbox_completed(Object? source, AsyncResult result) {
        generic_issue_command_completed(result, Event.CLOSED_MAILBOX, Event.CLOSE_MAILBOX_FAILED);
    }
    
    private uint on_closed_mailbox(uint state, uint event) {
        current_mailbox = null;
        
        return State.AUTHORIZED;
    }
    
    private uint on_close_mailbox_failed(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        AsyncParams params = (AsyncParams) object;
        params.err = new ImapError.COMMAND_FAILED("Unable to close mailbox \"%s\": %s",
            current_mailbox, params.cmd_response.to_string());
        
        return State.SELECTED;
    }
    
    //
    // logout
    //
    
    public async void logout_async(Cancellable? cancellable = null) throws Error {
        AsyncParams params = new AsyncParams(cancellable, logout_async.callback);
        fsm.issue(Event.LOGOUT, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
    }
    
    private uint on_logout(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        AsyncParams params = (AsyncParams) object;
        
        issue_command_async.begin(new LogoutCommand(), params, params.cancellable, on_logout_completed);
        
        params.do_yield = true;
        
        return State.LOGGING_OUT;
    }
    
    private void on_logout_completed(Object? source, AsyncResult result) {
        generic_issue_command_completed(result, Event.LOGOUT_SUCCESS, Event.LOGOUT_FAILED);
    }
    
    private uint on_logged_out(uint state, uint event, void *user) {
        fsm.do_post_transition(() => { logged_out(); });
        
        return State.LOGGED_OUT;
    }
    
    //
    // disconnect
    //
    
    public async void disconnect_async(Cancellable? cancellable = null) throws Error {
        AsyncParams params = new AsyncParams(cancellable, disconnect_async.callback);
        fsm.issue(Event.DISCONNECT, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
    }
    
    private uint on_disconnect(uint state, uint event, void *user, Object? object) {
        assert(disconnect_params == null);
        disconnect_params = (AsyncParams) object;
        
        cx.disconnect_async.begin(disconnect_params.cancellable, on_disconnect_completed);
        
        disconnect_params.do_yield = true;
        
        return State.DISCONNECTING;
    }
    
    private void on_disconnect_completed(Object? source, AsyncResult result) {
        assert(disconnect_params != null);
        
        try {
            cx.disconnect_async.end(result);
            fsm.issue(Event.DISCONNECTED);
            
            disconnected(DisconnectReason.LOCAL_CLOSE);
        } catch (Error err) {
            fsm.issue(Event.SEND_ERROR, null, null, err);
            disconnect_params.err = err;
        }
        
        Scheduler.on_idle(disconnect_params.cb);
        
        // don't hold a reference, the caller is doing that
        disconnect_params = null;
    }
    
    private uint on_disconnected(uint state, uint event) {
        // don't do inside signal handler -- although today drop_connection() doesn't fire signals or call
        // callbacks, it could in the future
        fsm.do_post_transition(() => { drop_connection(); });
        
        // although we could go to the DISCONNECTED state, that implies the object can be reused ...
        // while possible, that requires all state (not just the FSM) be reset at this point, and
        // it just seems simpler and less buggy to require the user to discard this object and
        // instantiate a new one
        
        return State.BROKEN;
    }
    
    //
    // error handling
    //
    
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
        
        AsyncParams params = (AsyncParams) object;
        params.err = new ImapError.NOT_CONNECTED("Not connected to %s", to_string());
        
        return state;
    }
    
    // This handles the situation where the user submits a command after the connection has been
    // logged out, terminated, or errored-out
    private uint on_late_command(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        AsyncParams params = (AsyncParams) object;
        params.err = new ImapError.NOT_CONNECTED("Connection to %s closing or closed", to_string());
        
        return state;
    }
    
    // This handles the situation where an unanticipated ServerResponse was received
    private uint on_dropped_response(uint state, uint event, void *user, Object? object) {
        ServerResponse server_response = (ServerResponse) object;
        
        debug("[%s] Dropped server response at %s: %s", to_string(), fsm.get_event_issued_string(state, event),
            server_response.to_string());
        
        return state;
    }
    
    private uint on_unauthenticated(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        AsyncParams params = (AsyncParams) object;
        params.err = new ImapError.UNAUTHENTICATED("Not authenticated with %s", to_string());
        
        return state;
    }
    
    private uint on_ignored_transition(uint state, uint event) {
#if VERBOSE_SESSION
        debug("Ignored transition: %s@%s", fsm.get_event_string(event), fsm.get_state_string(state));
#endif
        
        return state;
    }
    
    //
    // command submission
    //
    
    private async AsyncCommandResponse issue_command_async(Command cmd, Object? user,
        Cancellable? cancellable) {
        if (cx == null)
            return new AsyncCommandResponse(null, user, not_connected_err);
        
        try {
            yield cx.send_async(cmd, cancellable);
        } catch (Error send_err) {
            return new AsyncCommandResponse(null, user, send_err);
        }
        
        // send_async() should've tagged the Command, otherwise the completion_pending will fail
        assert(cmd.tag.is_tagged());
        
        // If the command didn't complete (i.e. a CompletionStatusResponse didn't return from the
        // server) in the context of send_async(), wait for it now
        if (!seen_completion_responses.has_key(cmd.tag)) {
            debug("[%s] Waiting for completion status response %s...", to_string(), cmd.tag.to_string());
            completion_pending.set(cmd.tag, new CommandCallback(issue_command_async.callback));
            yield;
        }
        
        // it should be seen now
        CompletionStatusResponse? completion_response;
        seen_completion_response.remove(cmd.tag, out completion_response);
        
        // if not, it's because of disconnection while waiting
        if (completion_response == null) {
            assert(cx == null);
            
            return new AsyncCommandResponse(null, user, not_connected_err);
        }
        
        return new AsyncCommandResponse(completion_response, user, null);
    }
    
    private void generic_issue_command_completion(AsyncResult result, Object? object) {
        AsyncCommandResponse async_response = issue_command_async.end(result);
        
        assert(async_response.user != null);
        AsyncParams params = (AsyncParams) async_response.user;
        
        params.completion_response = async_response.completion_response;
        params.err = async_response.err;
        
        // Issue a SEND_ERROR if an Error was detected, as that suggests none of the various server
        // response signals were fired to issue an event of their own
        if (async_response.err != null)
            fsm.issue(Event.SEND_ERROR, null, null, async_response.err);
        
        Scheduler.on_idle(params.cb);
    }
    
    //
    // network connection event handlers
    //
    
    private void on_network_connected() {
        debug("[%s] Connected to %s", to_full_string(), imap_endpoint.to_string());
    }
    
    private void on_network_disconnected() {
        debug("[%s] Disconnected from %s", to_full_string(), imap_endpoint.to_string());
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
    
    // Notify watchers of server responses
    private void notify_received_server_response(ServerResponse server_response) {
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
        
        // TODO: need to get this right ... it's possible for this signal to be fired in context of
        // cx.send_async() or after it's completed
        seen_completion_response.set(completion_status_response.tag, completion_status_response);
    }
    
    private void on_received_server_data(ServerData server_data) {
        // reschedule keepalive (traffic seen on channel)
        schedule_keepalive();
        
        // issue event change before the notifier so the ClientSession is up-to-date in case any of
        // the signal handlers call it for more information
        fsm.issue(Event.RECV_DATA, null, server_data, null);
        
        try {
            if (!notifier.notify(server_data))
                debug("[%s] Unable to notify of server data: %s", server_data.to_string());
        } catch (ImapError ierr) {
            debug("[%s] Failure notifying of server data: %s %s", server_data.to_string(),
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

