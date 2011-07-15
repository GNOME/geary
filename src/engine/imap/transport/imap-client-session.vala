/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSession {
    // 30 min keepalive required to maintain session; back off by 5 min for breathing room
    public const int MIN_KEEPALIVE_SEC = 25 * 60;
    public const int DEFAULT_KEEPALIVE_SEC = 3 * 60;
    
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
        public SourceFunc callback;
        
        public CommandCallback(SourceFunc callback) {
            this.callback = callback;
        }
    }
    
    private class AsyncCommandResponse {
        public CommandResponse? cmd_response { get; private set; }
        public Object? user { get; private set; }
        public Error? err { get; private set; }
        
        public AsyncCommandResponse(CommandResponse? cmd_response, Object? user, Error? err) {
            this.cmd_response = cmd_response;
            this.user = user;
            this.err = err;
        }
    }
    
    // Many of the async commands go through the FSM, and this is used to pass state around until
    // the multiple transitions are completed
    private class AsyncParams : Object {
        public Cancellable? cancellable;
        public SourceFunc cb;
        public CommandResponse? cmd_response = null;
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
        
        // async-response events
        CONNECTED,
        CONNECT_DENIED,
        LOGIN_SUCCESS,
        LOGIN_FAILED,
        SENT_COMMAND,
        SEND_COMMAND_FAILED,
        SELECTED,
        SELECT_FAILED,
        CLOSED_MAILBOX,
        CLOSE_MAILBOX_FAILED,
        LOGOUT_SUCCESS,
        LOGOUT_FAILED,
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
    
    private string server;
    private uint default_port;
    private Geary.State.Machine fsm;
    private ClientConnection? cx = null;
    private string? current_mailbox = null;
    private bool current_mailbox_readonly = false;
    private Gee.Queue<CommandCallback> cb_queue = new Gee.LinkedList<CommandCallback>();
    private Gee.Queue<CommandResponse> cmd_response_queue = new Gee.LinkedList<CommandResponse>();
    private CommandResponse current_cmd_response = new CommandResponse();
    private uint keepalive_id = 0;
    
    // state used only during connect and disconnect
    private bool awaiting_connect_response = false;
    private ServerData? connect_response = null;
    private AsyncParams? connect_params = null;
    private AsyncParams? disconnect_params = null;
    
    public virtual signal void connected() {
    }
    
    public virtual signal void authorized() {
    }
    
    public virtual signal void logged_out() {
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
    
    public virtual signal void unsolicited_expunged(MessageNumber msg) {
    }
    
    public virtual signal void unsolicited_exists(int exists) {
    }
    
    public virtual signal void unsolicited_recent(int recent) {
    }
    
    public virtual signal void unsolicited_flags(FetchResults flags) {
    }
    
    public ClientSession(string server, uint default_port) {
        this.server = server;
        this.default_port = default_port;
        
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
            new Geary.State.Mapping(State.CONNECTING, Event.CONNECTED, on_connected),
            new Geary.State.Mapping(State.CONNECTING, Event.CONNECT_DENIED, on_connect_denied),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.NOAUTH, Event.LOGIN, on_login),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.NOAUTH, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.NOAUTH, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGIN, Geary.State.nop),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGIN_SUCCESS, on_login_success),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGIN_FAILED, on_login_failed),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SELECT, on_select),
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
            new Geary.State.Mapping(State.SELECTING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTING, Event.SELECTED, on_selected),
            new Geary.State.Mapping(State.SELECTING, Event.SELECT_FAILED, on_select_failed),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.SELECTED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTED, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_ERROR, on_recv_error),
            
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_CMD, on_send_command),
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
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.RECV_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.LOGGED_OUT, Event.SEND_ERROR, on_send_error),
            
            new Geary.State.Mapping(State.DISCONNECTING, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.DISCONNECTING, Event.DISCONNECTED, on_disconnected),
            new Geary.State.Mapping(State.DISCONNECTING, Event.SEND_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.DISCONNECTING, Event.RECV_ERROR, Geary.State.nop),
            
            new Geary.State.Mapping(State.BROKEN, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.BROKEN, Event.DISCONNECT, Geary.State.nop)
        };
        
        fsm = new Geary.State.Machine(machine_desc, mappings, on_ignored_transition);
        fsm.set_logging(false);
    }
    
    public Tag generate_tag() throws ImapError {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", to_string());
        
        return cx.generate_tag();
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
        assert(object != null);
        
        assert(connect_params == null);
        connect_params = (AsyncParams) object;
        
        assert(cx == null);
        cx = new ClientConnection(server, ClientConnection.DEFAULT_PORT_TLS);
        cx.connected.connect(on_network_connected);
        cx.disconnected.connect(on_network_disconnected);
        cx.sent_command.connect(on_network_sent_command);
        cx.flush_failure.connect(on_network_flush_error);
        cx.received_status_response.connect(on_received_status_response);
        cx.received_server_data.connect(on_received_server_data);
        cx.received_bad_response.connect(on_received_bad_response);
        cx.receive_failure.connect(on_network_receive_failure);
        cx.deserialize_failure.connect(on_network_receive_failure);
        
        cx.connect_async.begin(connect_params.cancellable, on_connect_completed);
        
        connect_params.do_yield = true;
        
        return State.CONNECTING;
    }
    
    private void on_connect_completed(Object? source, AsyncResult result) {
        assert(connect_params != null);
        
        try {
            cx.connect_async.end(result);
        } catch (Error err) {
            fsm.issue(Event.SEND_ERROR, null, null, err);
            connect_params.err = err;
            
            Idle.add(connect_params.cb);
            connect_params = null;
            
            return;
        }
        
        // wait for the initial greeting from the server
        cb_queue.offer(new CommandCallback(on_connect_response_received));
        awaiting_connect_response = true;
    }
    
    private bool on_connect_response_received() {
        assert(connect_params != null);
        assert(connect_response != null);
        
        // initial greeting from server is an untagged response where the first parameter is a
        // status code
        try {
            StringParameter status_param = (StringParameter) connect_response.get_as(
                1, typeof(StringParameter));
            if (issue_status(Status.from_parameter(status_param), Event.CONNECTED, Event.CONNECT_DENIED,
                connect_response)) {
                connected();
            }
        } catch (ImapError imap_err) {
            connect_params.err = imap_err;
            fsm.issue(Event.CONNECT_DENIED);
        }
        
        Idle.add(connect_params.cb);
        connect_params = null;
        
        return false;
    }
    
    private uint on_connected(uint state, uint event, void *user) {
        return State.NOAUTH;
    }
    
    private uint on_connect_denied(uint state, uint event, void *user) {
        return State.BROKEN;
    }
    
    //
    // login
    //
    
    public async void login_async(string user, string pass, Cancellable? cancellable = null) throws Error {
        LoginParams params = new LoginParams(user, pass, cancellable, login_async.callback);
        fsm.issue(Event.LOGIN, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
    }
    
    private uint on_login(uint state, uint event, void *user, Object? object) {
        assert(object != null);
        
        LoginParams params = (LoginParams) object;
        
        issue_command_async.begin(new LoginCommand(cx.generate_tag(), params.user, params.pass),
            params, params.cancellable, on_login_completed);
        
        params.do_yield = true;
        
        return State.AUTHORIZING;
    }
    
    private void on_login_completed(Object? source, AsyncResult result) {
        if (generic_issue_command_completed(result, Event.LOGIN_SUCCESS, Event.LOGIN_FAILED))
            authorized();
    }
    
    private uint on_login_success(uint state, uint event, void *user) {
        return State.AUTHORIZED;
    }
    
    private uint on_login_failed(uint state, uint event, void *user) {
        return State.NOAUTH;
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
    public void enable_keepalives(int seconds = DEFAULT_KEEPALIVE_SEC) {
        if (seconds <= 0) {
            disable_keepalives();
            
            return;
        }
        
        if (keepalive_id != 0)
            Source.remove(keepalive_id);
        
        keepalive_id = Timeout.add_seconds(seconds, on_keepalive);
    }
    
    /**
     * Returns true if keepalives are disactivated, false if already disabled.
     */
    public bool disable_keepalives() {
        if (keepalive_id == 0)
            return false;
        
        Source.remove(keepalive_id);
        keepalive_id = 0;
        
        return true;
    }
    
    private bool on_keepalive() {
        try {
            send_command_async.begin(new NoopCommand(generate_tag()), null, on_keepalive_completed);
        } catch (ImapError ierr) {
            message("Unable to keepalive %s, halting attempts: %s", to_string(), ierr.message);
            
            keepalive_id = 0;
            
            return false;
        }
        
        return true;
    }
    
    private void on_keepalive_completed(Object? source, AsyncResult result) {
        NoopResults results;
        try {
            results = NoopResults.decode(send_command_async.end(result));
        } catch (Error err) {
            message("Keepalive error: %s", err.message);
            
            return;
        }
        
        if (results.status_response.status != Status.OK) {
            debug("Keepalive failed: %s", results.status_response.to_string());
            
            return;
        }
        
        if (results.expunged != null) {
            foreach (MessageNumber msg in results.expunged)
                unsolicited_expunged(msg);
        }
        
        if (results.has_exists())
            unsolicited_exists(results.exists);
        
        if (results.has_recent())
            unsolicited_recent(results.recent);
        
        if (results.flags != null) {
            foreach (FetchResults flags in results.flags)
                unsolicited_flags(flags);
        }
    }
    
    //
    // send commands
    //
    
    public async CommandResponse send_command_async(Command cmd, Cancellable? cancellable = null) 
        throws Error {
        // look for special commands that we wish to handle directly, as they affect the state
        // machine
        //
        // TODO: Convert commands into proper calls to avoid throwing an exception
        if (cmd.has_name(LoginCommand.NAME) || cmd.has_name(LogoutCommand.NAME)
            || cmd.has_name(SelectCommand.NAME) || cmd.has_name(ExamineCommand.NAME)
            || cmd.has_name(CloseCommand.NAME)) {
            throw new ImapError.NOT_SUPPORTED("Use direct calls rather than commands");
        }
        
        SendCommandParams params = new SendCommandParams(cmd, cancellable, send_command_async.callback);
        fsm.issue(Event.SEND_CMD, null, params);
        
        if (params.do_yield)
            yield;
        
        if (params.err != null)
            throw params.err;
        
        return params.cmd_response;
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
        
        Command cmd;
        if (params.is_select)
            cmd = new SelectCommand(cx.generate_tag(), params.mailbox);
        else
            cmd = new ExamineCommand(cx.generate_tag(), params.mailbox);
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
        
        AsyncParams params = (AsyncParams) object;
        
        issue_command_async.begin(new CloseCommand(cx.generate_tag()), params, params.cancellable,
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
        
        issue_command_async.begin(new LogoutCommand(cx.generate_tag()), params, params.cancellable,
            on_logout_completed);
        
        params.do_yield = true;
        
        return State.LOGGING_OUT;
    }
    
    private void on_logout_completed(Object? source, AsyncResult result) {
        if (generic_issue_command_completed(result, Event.LOGOUT_SUCCESS, Event.LOGOUT_FAILED))
            logged_out();
    }
    
    private uint on_logged_out(uint state, uint event, void *user) {
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
        assert(object != null);
        
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
        
        Idle.add(disconnect_params.cb);
        disconnect_params = null;
    }
    
    private uint on_disconnected(uint state, uint event) {
        cx = null;
        
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
        debug("Send error on %s: %s", to_full_string(), err.message);
        
        cx = null;
        Idle.add(on_fire_send_error_signal);
        
        return State.BROKEN;
    }
    
    private bool on_fire_send_error_signal() {
        disconnected(DisconnectReason.LOCAL_ERROR);
        
        return false;
    }
    
    private uint on_recv_error(uint state, uint event, void *user, Object? object, Error? err) {
        assert(err != null);
        debug("Receive error on %s: %s", to_full_string(), err.message);
        
        cx = null;
        Idle.add(on_fire_recv_error_signal);
        
        return State.BROKEN;
    }
    
    private bool on_fire_recv_error_signal() {
        disconnected(DisconnectReason.REMOTE_ERROR);
        
        return false;
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
    
    private bool issue_status(Status status, Event ok_event, Event error_event, Object? object) {
        fsm.issue((status == Status.OK) ? ok_event : error_event, null, object);
        
        return (status == Status.OK);
    }
    
    private async AsyncCommandResponse issue_command_async(Command cmd, Object? user = null,
        Cancellable? cancellable = null) {
        if (cx == null) {
            return new AsyncCommandResponse(null, user,
                new ImapError.NOT_CONNECTED("Not connected to %s", server));
        }
        
        try {
            yield cx.send_async(cmd, cancellable);
        } catch (Error err) {
            return new AsyncCommandResponse(null, user, err);
        }
        
        cb_queue.offer(new CommandCallback(issue_command_async.callback));
        yield;
        
        CommandResponse? cmd_response = cmd_response_queue.poll();
        assert(cmd_response != null);
        assert(cmd_response.is_sealed());
        assert(cmd_response.status_response.tag.equals(cmd.tag));
        
        return new AsyncCommandResponse(cmd_response, user, null);
    }
    
    private bool generic_issue_command_completed(AsyncResult result, Event ok_event, Event error_event) {
        AsyncCommandResponse async_response = issue_command_async.end(result);
        
        assert(async_response.user != null);
        AsyncParams params = (AsyncParams) async_response.user;
        
        params.cmd_response = async_response.cmd_response;
        params.err = async_response.err;
        
        bool success;
        if (async_response.err != null) {
            fsm.issue(Event.SEND_ERROR, null, null, async_response.err);
            success = false;
        } else {
            issue_status(async_response.cmd_response.status_response.status, ok_event, error_event,
                params);
            success = true;
        }
        
        Idle.add(params.cb);
        
        return success;
    }
    
    //
    // network connection event handlers
    //
    
    private void on_network_connected() {
#if VERBOSE_SESSION
        debug("Connected to %s", server);
#endif
    }
    
    private void on_network_disconnected() {
#if VERBOSE_SESSION
        debug("Disconnected from %s", server);
#endif
    }
    
    private void on_network_sent_command(Command cmd) {
#if VERBOSE_SESSION
        debug("Sent command %s", cmd.to_string());
#endif
    }
    
    private void on_network_flush_error(Error err) {
        debug("Flush error on %s: %s", to_string(), err.message);
        fsm.issue(Event.SEND_ERROR, null, null, err);
    }
    
    private void on_received_status_response(StatusResponse status_response) {
        assert(!current_cmd_response.is_sealed());
        current_cmd_response.seal(status_response);
        assert(current_cmd_response.is_sealed());
        
        cmd_response_queue.offer(current_cmd_response);
        current_cmd_response = new CommandResponse();
        
        CommandCallback? cmd_callback = cb_queue.poll();
        assert(cmd_callback != null);
        
        Idle.add(cmd_callback.callback);
    }
    
    private void on_received_server_data(ServerData server_data) {
        // The first response from the server is an untagged status response, which is considered
        // ServerData in our model.  This captures that and treats it as such.
        if (awaiting_connect_response) {
            awaiting_connect_response = false;
            connect_response = server_data;
            
            CommandCallback? cmd_callback = cb_queue.poll();
            assert(cmd_callback != null);
            
            Idle.add(cmd_callback.callback);
            
            return;
        }
        
        current_cmd_response.add_server_data(server_data);
    }
    
    private void on_received_bad_response(RootParameters root, ImapError err) {
        debug("Received bad response %s: %s", root.to_string(), err.message);
    }
    
    private void on_network_receive_failure(Error err) {
        debug("Receive failed: %s", err.message);
        fsm.issue(Event.RECV_ERROR, null, null, err);
    }
    
    public string to_string() {
        return "ClientSession:%s:%u".printf(server, default_port);
    }
    
    public string to_full_string() {
        return "%s [%s]".printf(to_string(), fsm.get_state_string(fsm.get_state()));
    }
}

