/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * High-level interface to a single IMAP server connection.
 *
 * The client session is responsible for opening, maintaining and
 * closing a TCP connection to an IMAP server. When opening, the
 * session will obtain and maintain capabilities, establish a StartTLS
 * session if appropriate, authenticate, and obtain
 * connection-specific information about the server such as the name
 * used for the INBOX and any mailbox namespaces. When connecting has
 * completed successfully, the connection will be in the IMAP
 * authenticated state.
 *
 * Any IMAP commands that affect the IMAP connection's state (LOGIN,
 * LOGOUT, SELECT, etc) must be executed by calling the appropriate
 * method on this object. For example, call `login_async` rather than
 * sending a {@link LoginCommand}. Other commands can be sent via
 * {@link send_command_async} and {@link send_multiple_commands_async}.
 */
public class Geary.Imap.ClientSession : BaseObject, Logging.Source {

    /**
     * Maximum keep-alive interval required to maintain a session.
     *
     * RFC 3501 requires servers have a minimum idle timeout of 30
     * minutes, so the keep-alive interval should be set to less than
     * this.
     */
    public const uint MAX_KEEPALIVE_SEC = 30 * 60;

    /**
     * Recommended keep-alive interval required to maintain a session.
     *
     * Although many servers will allow a timeout of at least what RFC
     * 3501 requires, devices in between (e.g. NAT gateways) may have
     * much shorter timeouts. Thus this is set much lower than what
     * the RFC allows.
     */
    public const uint RECOMMENDED_KEEPALIVE_SEC = (10 * 60) - 30;

    /**
     * An aggressive keep-alive interval for polling for updates.
     *
     * Since a server may respond to NOOP with untagged responses for
     * new messages or status updates, this is a useful timeout for
     * polling for changes.
     */
    public const uint AGGRESSIVE_KEEPALIVE_SEC = 2 * 60;

    /**
     * Default keep-alive interval in the Selected state.
     *
     * This uses @{link AGGRESSIVE_KEEPALIVE_SEC} so that without IMAP
     * IDLE, changes to the mailbox are still noticed without too much
     * delay.
     */
    public const uint DEFAULT_SELECTED_KEEPALIVE_SEC = AGGRESSIVE_KEEPALIVE_SEC;

    /**
     * Default keep-alive interval in the Selected state with IDLE.
     *
     * This uses @{link RECOMMENDED_KEEPALIVE_SEC} because IMAP IDLE
     * will notify about changes to the mailbox as it happens .
     */
    public const uint DEFAULT_SELECTED_WITH_IDLE_KEEPALIVE_SEC = RECOMMENDED_KEEPALIVE_SEC;

    /** Default keep-alive interval when not in the Selected state. */
    public const uint DEFAULT_UNSELECTED_KEEPALIVE_SEC = RECOMMENDED_KEEPALIVE_SEC;

    /** Default time to wait for the server greeting when connecting. */
    public const uint DEFAULT_GREETING_TIMEOUT_SEC =
        Command.DEFAULT_RESPONSE_TIMEOUT_SEC;


    /**
     * The various states an IMAP {@link ClientSession} may be in at any moment.
     *
     * These don't exactly match the states in the IMAP specification.  For one, they count
     * transitions as states unto themselves (due to network latency and the asynchronous nature
     * of ClientSession's interface).  Also, the LOGOUT state has been melded
     * into {@link ProtocolState.NOT_CONNECTED} on the presumption that the nuances of a disconnected or
     * disconnecting session is uninteresting to the caller.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-3]]
     *
     * @see protocol_state
     */
    public enum ProtocolState {
        NOT_CONNECTED,
        CONNECTING,
        UNAUTHORIZED,
        AUTHORIZING,
        AUTHORIZED,
        SELECTING,
        SELECTED,
        /**
         * Indicates the {@link ClientSession} is closing a ''mailbox'', i.e. a folder, not the
         * connection itself.
         */
        CLOSING_MAILBOX
    }

    public enum DisconnectReason {
        NULL,
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

        public override async Object? execute_async(GLib.Cancellable? cancellable)
            throws GLib.Error {
            // The command's should_send cancellable will be used to
            // cancel the command if needed, so don't need to check or
            // pass this method's cancellable through.
            this.response = yield owner.submit_command(cmd);
            return this.response;
        }
    }

    private enum State {
        // initial state
        NOT_CONNECTED,

        // canonical IMAP session states
        NOAUTH,
        AUTHORIZED,
        SELECTED,
        LOGOUT,

        // transitional states
        CONNECTING,
        AUTHORIZING,
        SELECTING,
        CLOSING_MAILBOX,

        // terminal state
        CLOSED,

        COUNT
    }

    private static string state_to_string(uint state) {
        return ObjectUtils.to_enum_nick(typeof(State), state);
    }

    private enum Event {
        // user-initiated events
        CONNECT,
        DISCONNECT,

        // command-initiated events
        LOGIN,
        SEND_CMD,
        SELECT,
        CLOSE_MAILBOX,
        LOGOUT,

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
        "Geary.Imap.ClientSession", State.NOT_CONNECTED, State.COUNT, Event.COUNT,
        state_to_string, event_to_string);


    /**
     * Returns the current IMAP protocol state for the session.
     */
    public ProtocolState protocol_state {
        get {
            var state = ProtocolState.NOT_CONNECTED;
            switch (fsm.state) {
            case State.NOT_CONNECTED:
            case State.LOGOUT:
            case State.CLOSED:
                state = NOT_CONNECTED;
                break;

            case State.NOAUTH:
                state = UNAUTHORIZED;
                break;

            case State.AUTHORIZED:
                state = AUTHORIZED;
                break;

            case State.SELECTED:
                state = SELECTED;
                break;

            case State.CONNECTING:
                state = CONNECTING;
                break;

            case State.AUTHORIZING:
                state = AUTHORIZING;
                break;

            case State.SELECTING:
                state = SELECTING;
                break;

            case State.CLOSING_MAILBOX:
                state = CLOSING_MAILBOX;
                break;
            }
            return state;
        }
    }

    /** Specifies the reason the session was disconnected, if any. */
    public DisconnectReason disconnected { get; private set; default = NULL; }

    /**
     * Set of IMAP extensions reported as being supported by the server.
     *
     * The capabilities that an IMAP session offers changes over time,
     * for example after login or STARTTLS. The instance assigned to
     * this property will change as these change and the instance's
     * {@link Capabilities.revision} property will also monotonically
     * increase over the lifetime of a single session.
     */
    public Capabilities capabilities {
        get; private set; default = new Capabilities.empty(0);
    }

    /** Determines if this session supports the IMAP IDLE extension. */
    public bool is_idle_supported {
        get { return this.capabilities.has_capability(Capabilities.IDLE); }
    }

    /**
     * The server's greeting, if any.
     *
     * This will be null up until the session has successfully
     * connected and the server has responded with a greeting.
     */
    public StatusResponse? server_greeting { get; private set; default = null; }

    /** The currently selected mailbox, if any. */
    public MailboxSpecifier? selected_mailbox = null;

    /**
     * Specifies if the current selected state is readonly.
     *
     * This property specifies if the current selected state was
     * entered by a SELECT command -- in which case mailbox access is
     * read-write, or by an EXAMINE command -- in which case mailbox
     * access is read-only.
     */
    public bool selected_readonly = false;

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return ClientService.LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;

    /**
     * Determines when the last successful command response was received.
     *
     * Returns the system wall clock time the last successful command
     * response was received, in microseconds since the UNIX epoch.
     */
    internal int64 last_seen { get; private set; default = 0; }

    // While the following inbox and namespace data should be server
    // specific, there is a small chance they will differ between
    // connections if the connections connect to different servers in
    // a cluster, or if configuration changes between connections. We
    // do assume however that once connected, this information will
    // remain the same. This information becomes current only after
    // initiate_session_async() has successfully completed.

    /** Records the actual name and delimiter used for the inbox */
    internal MailboxInformation? inbox { get; private set; default = null; }

    /** The quirks being used by this session. */
    internal Quirks quirks { get; set; }

    // Locations personal mailboxes for this session
    private Gee.List<Namespace> personal_namespaces = new Gee.ArrayList<Namespace>();

    // Locations of other user's mailboxes for this session
    private Gee.List<Namespace> user_namespaces = new Gee.ArrayList<Namespace>();

    // The locations of shared mailboxes for this sesion
    private Gee.List<Namespace> shared_namespaces = new Gee.ArrayList<Namespace>();

    private Endpoint imap_endpoint;
    private Geary.State.Machine fsm;
    private ClientConnection? cx = null;

    private uint keepalive_id = 0;
    private uint selected_keepalive_secs = 0;
    private uint unselected_keepalive_secs = 0;
    private uint selected_with_idle_keepalive_secs = 0;

    private Command? state_change_cmd = null;
    private Nonblocking.Semaphore? connect_waiter = null;
    private Error? connect_err = null;

    private Gee.Map<string,Namespace> namespaces = new Gee.HashMap<string,Namespace>();



    //
    // Connection state changes
    //

    /** Emitted when an IMAP command status response is received. */
    public signal void status_response_received(StatusResponse status_response);

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


    public ClientSession(Endpoint imap_endpoint, Quirks quirks) {
        this.imap_endpoint = imap_endpoint;
        this.quirks = quirks;

        Geary.State.Mapping[] mappings = {
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.CONNECT, on_connect),
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.NOT_CONNECTED, Event.DISCONNECT, Geary.State.nop),

            new Geary.State.Mapping(State.CONNECTING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.CONNECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.CONNECTING, Event.LOGIN, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_CMD, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.SELECT, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.CLOSE_MAILBOX, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.LOGOUT, on_early_command),
            new Geary.State.Mapping(State.CONNECTING, Event.CONNECTED, on_connected),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_STATUS, on_connecting_recv_status),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.CONNECTING, Event.SEND_ERROR, on_connecting_send_recv_error),
            new Geary.State.Mapping(State.CONNECTING, Event.RECV_ERROR, on_connecting_send_recv_error),
            new Geary.State.Mapping(State.CONNECTING, Event.TIMEOUT, on_connecting_timeout),

            new Geary.State.Mapping(State.NOAUTH, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.NOAUTH, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGIN, on_login),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.NOAUTH, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.NOAUTH, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_COMPLETION, on_recv_status),
            new Geary.State.Mapping(State.NOAUTH, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.NOAUTH, Event.RECV_ERROR, on_recv_error),

            new Geary.State.Mapping(State.AUTHORIZING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.AUTHORIZING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGIN, on_logging_in),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_CMD, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SELECT, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.CLOSE_MAILBOX, on_unauthenticated),
            new Geary.State.Mapping(State.AUTHORIZING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_COMPLETION, on_login_recv_completion),
            new Geary.State.Mapping(State.AUTHORIZING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZING, Event.RECV_ERROR, on_recv_error),

            new Geary.State.Mapping(State.AUTHORIZED, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.AUTHORIZED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.AUTHORIZED, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.AUTHORIZED, Event.CLOSE_MAILBOX, on_not_selected),
            new Geary.State.Mapping(State.AUTHORIZED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_COMPLETION, on_recv_status),
            new Geary.State.Mapping(State.AUTHORIZED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.AUTHORIZED, Event.RECV_ERROR, on_recv_error),

            new Geary.State.Mapping(State.SELECTING, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.SELECTING, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTING, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTING, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTING, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTING, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_COMPLETION, on_selecting_recv_completion),
            new Geary.State.Mapping(State.SELECTING, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTING, Event.RECV_ERROR, on_recv_error),

            new Geary.State.Mapping(State.SELECTED, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.SELECTED, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.SELECTED, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.SELECTED, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.SELECTED, Event.SELECT, on_select),
            new Geary.State.Mapping(State.SELECTED, Event.CLOSE_MAILBOX, on_close_mailbox),
            new Geary.State.Mapping(State.SELECTED, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_COMPLETION, on_recv_status),
            new Geary.State.Mapping(State.SELECTED, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.SELECTED, Event.RECV_ERROR, on_recv_error),

            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_CMD, on_send_command),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SELECT, on_select),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.CLOSE_MAILBOX, on_not_selected),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.LOGOUT, on_logout),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_STATUS, on_recv_status),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_COMPLETION, on_closing_recv_completion),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.SEND_ERROR, on_send_error),
            new Geary.State.Mapping(State.CLOSING_MAILBOX, Event.RECV_ERROR, on_recv_error),

            new Geary.State.Mapping(State.LOGOUT, Event.CONNECT, on_already_connected),
            new Geary.State.Mapping(State.LOGOUT, Event.DISCONNECT, on_disconnect),
            new Geary.State.Mapping(State.LOGOUT, Event.LOGIN, on_already_logged_in),
            new Geary.State.Mapping(State.LOGOUT, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.LOGOUT, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.LOGOUT, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.LOGOUT, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.LOGOUT, Event.RECV_STATUS, on_logging_out_recv_status),
            new Geary.State.Mapping(State.LOGOUT, Event.RECV_COMPLETION, on_logging_out_recv_completion),
            new Geary.State.Mapping(State.LOGOUT, Event.RECV_ERROR, on_recv_error),
            new Geary.State.Mapping(State.LOGOUT, Event.SEND_ERROR, on_send_error),

            new Geary.State.Mapping(State.CLOSED, Event.CONNECT, on_late_command),
            new Geary.State.Mapping(State.CLOSED, Event.DISCONNECT, Geary.State.nop),
            new Geary.State.Mapping(State.CLOSED, Event.LOGIN, on_late_command),
            new Geary.State.Mapping(State.CLOSED, Event.SEND_CMD, on_late_command),
            new Geary.State.Mapping(State.CLOSED, Event.SELECT, on_late_command),
            new Geary.State.Mapping(State.CLOSED, Event.CLOSE_MAILBOX, on_late_command),
            new Geary.State.Mapping(State.CLOSED, Event.LOGOUT, on_late_command),
            new Geary.State.Mapping(State.CLOSED, Event.RECV_STATUS, on_dropped_response),
            new Geary.State.Mapping(State.CLOSED, Event.RECV_COMPLETION, on_dropped_response),
            new Geary.State.Mapping(State.CLOSED, Event.SEND_ERROR, Geary.State.nop),
            new Geary.State.Mapping(State.CLOSED, Event.RECV_ERROR, Geary.State.nop),
        };

        this.fsm = new Geary.State.Machine(
            machine_desc,
            mappings,
            on_ignored_transition
        );
        this.fsm.notify["state"].connect(
            () => this.notify_property("protocol_state")
        );
    }

    ~ClientSession() {
        switch (fsm.state) {
            case State.NOT_CONNECTED:
            case State.CLOSED:
                // no problem-o
            break;

            default:
                GLib.warning("ClientSession ref dropped while still active");
        }
    }

    /**
     * Returns the list of known personal mailbox namespaces.
     *
     * A personal namespace is a common prefix of a set of mailboxes
     * that belong to the currently authenticated account. It may
     * contain the account's Inbox and Sent mailboxes, for example.
     *
     * The list will be empty when the session is not in the
     * authenticated or selected states, it will contain at least one
     * after having successfully logged in.
     *
     * See [[https://tools.ietf.org/html/rfc2342|RFC 2342]] for more
     * information.
     */
    public Gee.List<Namespace> get_personal_namespaces() {
        return this.personal_namespaces.read_only_view;
    }

    /**
     * Returns the list of known shared mailbox namespaces.
     *
     * A shared namespace is a common prefix of a set of mailboxes
     * that are normally accessible by multiple accounts on the
     * server, for example shared email mailboxes and NNTP news
     * mailboxes.
     *
     * The list will be empty when the session is not in the
     * authenticated or selected states, it will only be non-empty
     * after having successfully logged in and if the server supports
     * shared mailboxes.
     *
     * See [[https://tools.ietf.org/html/rfc2342|RFC 2342]] for more
     * information.
     */
    public Gee.List<Namespace> get_shared_namespaces() {
        return this.shared_namespaces.read_only_view;
    }

    /**
     * Returns the list of known other-users mailbox namespaces.
     *
     * An other-user namespace is a common prefix of a set of
     * mailboxes that are the personal mailboxes of other accounts on
     * the server. These would not normally be accessible to the
     * currently authenticated account unless the account has
     * administration privileges.
     *
     * The list will be empty when the session is not in the
     * authenticated or selected states, it will only be non-empty
     * after having successfully logged in and if the server or
     * account supports accessing other account's mailboxes.
     *
     * See [[https://tools.ietf.org/html/rfc2342|RFC 2342]] for more
     * information.
     */
    public Gee.List<Namespace> get_other_users_namespaces() {
        return this.user_namespaces.read_only_view;
    }

    /**
     * Determines the SELECT-able mailbox name for a specific folder path.
     */
    public MailboxSpecifier get_mailbox_for_path(FolderPath path)
        throws ImapError {
        string? delim = get_delimiter_for_path(path);
        return new MailboxSpecifier.from_folder_path(path, this.inbox.mailbox, delim);
    }

    /**
     * Determines the folder path for a mailbox name.
     */
    public FolderPath get_path_for_mailbox(FolderRoot root,
                                           MailboxSpecifier mailbox)
        throws ImapError {
        string? delim = get_delimiter_for_mailbox(mailbox);
        return mailbox.to_folder_path(root, delim, this.inbox.mailbox);
    }

    /**
     * Determines the mailbox hierarchy delimiter for a given folder path.
     *
     * The returned delimiter be null if a namespace (INBOX, personal,
     * etc) for the path does not exist, or if the namespace is flat.
     */
    public string? get_delimiter_for_path(FolderPath path)
    throws ImapError {
        string? delim = null;

        FolderRoot root = (FolderRoot) path.get_root();
        if (root.inbox.equal_to(path) ||
            root.inbox.is_descendant(path)) {
            delim = this.inbox.delim;
        } else {
            Namespace? ns = null;
            FolderPath? search = path;
            while (ns == null && search != null) {
                ns = this.namespaces.get(search.name);
                search = search.parent;
            }
            if (ns == null) {
                // fall back to the default personal namespace
                if (this.personal_namespaces.is_empty) {
                    throw new ImapError.UNAVAILABLE("No personal namespace");
                }
                ns = this.personal_namespaces[0];
            }

            delim = ns.delim;
        }
        return delim;
    }

    /**
     * Determines the mailbox hierarchy delimiter for a given mailbox name.
     *
     * The returned delimiter be null if a namespace (INBOX, personal,
     * etc) for the mailbox does not exist, or if the namespace is flat.
     */
    public string? get_delimiter_for_mailbox(MailboxSpecifier mailbox)
    throws ImapError {
        string name = mailbox.name;
        string? delim = null;

        string inbox_name = this.inbox.mailbox.name;
        string? inbox_delim = this.inbox.delim;
        if (inbox_name == name ||
            (inbox_delim != null && inbox_name.has_prefix(name + inbox_delim))) {
            delim = this.inbox.delim;
        } else {
            foreach (Namespace ns in this.namespaces.values) {
                if (name.has_prefix(ns.prefix)) {
                    delim = ns.delim;
                    break;
                }
            }
        }
        return delim;
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
     * This performs no transaction or session initiation with the
     * server.  See {@link login_async} and {@link
     * initiate_session_async} for next steps.
     *
     * If the connection fails (if this call throws an Error) the
     * ClientSession will be disconnected, even if the error was from
     * the server (that is, not a network problem).  The {@link
     * ClientSession} should be discarded.
     */
    public async void connect_async(
        uint greeting_timeout_sec = DEFAULT_GREETING_TIMEOUT_SEC,
        GLib.Cancellable? cancellable = null
    ) throws GLib.Error {
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
            fsm.issue(Event.CONNECTED);
        } catch (GLib.Error err) {
            fsm.issue(Event.SEND_ERROR, null, null, err);
            throw err;
        }

        // set up timer to wait for greeting from server
        Scheduler.Scheduled timeout = Scheduler.after_sec(
            greeting_timeout_sec, on_greeting_timeout
        );

        // wait for the initial greeting or a timeout ... this
        // prevents the caller from turning around and issuing a
        // command while still in CONNECTING state
        try {
            yield connect_waiter.wait_async(cancellable);
        } catch (GLib.IOError.CANCELLED err) {
            connect_err = err;
        }

        // cancel the timeout, if it's not already fired
        timeout.cancel();

        // if session was denied or timeout, ensure the session is disconnected and throw the
        // original Error ... connect_async shouldn't leave the session in the CONNECTING state,
        // but completely disconnected if unsuccessful
        if (connect_err != null) {
            try {
                yield disconnect_async(cancellable);
            } catch (Error err) {
                warning(
                    "Error disconnecting after a failed connect attempt: %s",
                    err.message
                );
            }

            throw connect_err;
        }
    }

    private bool on_greeting_timeout() {
        // if still in CONNECTING state, the greeting never arrived
        if (fsm.state == State.CONNECTING)
            fsm.issue(Event.TIMEOUT);

        return false;
    }

    private uint on_connect(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;

        assert(cx == null);
        cx = new ClientConnection(imap_endpoint, this.quirks);
        cx.set_logging_parent(this);
        cx.send_failure.connect(on_network_send_error);
        cx.received_status_response.connect(on_received_status_response);
        cx.received_server_data.connect(on_received_server_data);
        cx.received_bytes.connect(on_received_bytes);
        cx.received_bad_response.connect(on_received_bad_response);
        cx.receive_failure.connect(on_network_receive_failure);

        assert(connect_waiter == null);
        connect_waiter = new Nonblocking.Semaphore();

        params.proceed = true;

        return State.CONNECTING;
    }

    private void drop_connection() {
        unschedule_keepalive();

        if (cx != null) {
            cx.received_status_response.disconnect(on_received_status_response);
            cx.received_server_data.disconnect(on_received_server_data);
            cx.received_bytes.disconnect(on_received_bytes);
            cx.received_bad_response.disconnect(on_received_bad_response);
            cx.receive_failure.disconnect(on_network_receive_failure);

            cx = null;
        }
    }

    private uint on_connected(uint state, uint event) {
        debug("Connected to %s", imap_endpoint.to_string());

        // stay in current state -- wait for initial status response
        // to move into NOAUTH or LOGOUT
        return state;
    }

    private uint on_disconnect(uint state,
                               uint event,
                               void *user = null,
                               GLib.Object? object = null,
                               GLib.Error? err = null) {
        debug("Disconnected from %s", this.imap_endpoint.to_string());
        MachineParams params = (MachineParams) object;
        params.proceed = true;
        return State.CLOSED;
    }

    private uint on_connecting_recv_status(uint state, uint event, void *user, Object? object) {
        StatusResponse status_response = (StatusResponse) object;

        uint new_state = State.NOAUTH;
        if (status_response.status != Status.OK) {
            // Don't need to manually disconnect here, by setting
            // connect_err here that will be done in connect_async
            this.connect_err = new ImapError.UNAVAILABLE(
                "Session denied: %s", status_response.get_text()
            );
            new_state = State.LOGOUT;
        }

        this.server_greeting = status_response;
        debug("Server greeting: %s", status_response.get_text());

        try {
            this.connect_waiter.notify();
        } catch (GLib.Error err) {
            warning(
                "Unable to notify connect_waiter of connection: %s",
                err.message
            );
        }

        return new_state;
    }

    private uint on_connecting_timeout(uint state, uint event) {
        // Don't need to manually disconnect here, by setting
        // connect_err here that will be done in connect_async
        this.connect_err = new GLib.IOError.TIMED_OUT(
            "Session greeting not sent"
        );

        try {
            connect_waiter.notify();
        } catch (Error err) {
            warning(
                "Unable to notify connect_waiter of timeout: %s", err.message
            );
        }

        return State.LOGOUT;
    }

    /**
     * Performs the LOGIN command using the supplied credentials.
     *
     * Throws {@link ImapError.UNAUTHENTICATED} if the credentials are
     * bad, unsupported, or if authentication actually failed. Returns
     * the status response for the command otherwise.
     *
     * @see initiate_session_async
     */
    public async StatusResponse login_async(Geary.Credentials credentials,
                                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        Command? cmd = null;
        switch (credentials.supported_method) {
        case Geary.Credentials.Method.PASSWORD:
            cmd = new LoginCommand(
                credentials.user,
                credentials.token,
                cancellable
            );
            break;

        case Geary.Credentials.Method.OAUTH2:
            if (!capabilities.has_setting(Capabilities.AUTH,
                                          Capabilities.AUTH_XOAUTH2)) {
                throw new ImapError.UNAUTHENTICATED(
                    "OAuth2 authentication not supported for %s", to_string()
                );
            }
            cmd = new AuthenticateCommand.oauth2(
                credentials.user,
                credentials.token,
                cancellable
            );
            break;

        default:
            throw new ImapError.UNAUTHENTICATED(
                "Credentials method %s not supported for: %s",
                credentials.supported_method.to_string(),
                to_string()
            );
        }

        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.LOGIN, null, params);

        if (params.err != null)
            throw params.err;

        // should always proceed; only an Error could change this
        assert(params.proceed);

        StatusResponse response = yield submit_command(cmd);
        if (response.status != Status.OK) {
            // Throw an error indicating auth failed here, unless
            // there is a status response and it indicates that the
            // server is merely reporting login as being unavailable,
            // then don't since the creds might actually be fine.
            ResponseCode? code = response.response_code;
            if (code != null) {
                ResponseCodeType? code_type = code.get_response_code_type();
                if (code_type != null) {
                    switch (code_type.value) {
                    case ResponseCodeType.UNAVAILABLE:
                        throw new ImapError.UNAVAILABLE(
                            "Login restricted: %s: ", response.to_string()
                        );

                    case ResponseCodeType.AUTHENTICATIONFAILED:
                        // pass through to the error being thrown below
                        break;

                    default:
                        throw new ImapError.SERVER_ERROR(
                            "Login error: %s: ", response.to_string()
                        );
                    }
                }
            }

            throw new ImapError.UNAUTHENTICATED(
                "Bad credentials: %s: ", response.to_string()
            );
        }

        return cmd.status;
    }

    /**
     * Prepares the connection and performs a login using the supplied credentials.
     *
     * Preparing the connection includes attempting compression and using STARTTLS if necessary.
     * {@link Capabilities} are also retrieved automatically at the right time to ensure the best
     * results are available with {@link capabilities}.
     */
    public async void initiate_session_async(Geary.Credentials credentials,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        // If no capabilities available, get them now
        if (this.capabilities.is_empty()) {
            yield send_command_async(new CapabilityCommand(cancellable));
        }

        var last_capabilities = this.capabilities.revision;

        if (imap_endpoint.tls_method == TlsNegotiationMethod.START_TLS) {
            if (!this.capabilities.has_capability(Capabilities.STARTTLS)) {
                throw new ImapError.NOT_SUPPORTED(
                    "STARTTLS unavailable for %s", to_string());
            }

            debug("Attempting STARTTLS...");
            StatusResponse resp = yield send_command_async(
                new StarttlsCommand(cancellable)
            );

            if (resp.status == Status.OK) {
                yield cx.starttls_async(cancellable);
                debug("STARTTLS completed");
            } else {
                // Throw an exception and fail rather than send
                // credentials under suspect conditions
                throw new ImapError.NOT_SUPPORTED(
                    "STARTTLS refused by %s: %s", to_string(),
                    resp.status.to_string()
                );
            }

            if (last_capabilities == capabilities.revision) {
                // Per RFC3501 §6.2.1, after TLS is established, all
                // capabilities must be cleared and re-acquired to
                // mitigate main-in-the-middle attacks. If the TLS
                // command response did not update capabilities,
                // explicitly do so now.
                yield send_command_async(new CapabilityCommand(cancellable));
                last_capabilities = this.capabilities.revision;
            }
        }

        // Login after STARTTLS
        yield login_async(credentials, cancellable);

        // if new capabilities not offered after login, get them now
        if (last_capabilities == capabilities.revision) {
            yield send_command_async(new CapabilityCommand(cancellable));
        }

        var list_results = new Gee.ArrayList<MailboxInformation>();
        ulong list_id = this.list.connect(
            (mailbox) => { list_results.add(mailbox); }
        );
        try {
            // Determine what this connection calls the inbox
            Imap.StatusResponse response = yield send_command_async(
                new ListCommand(MailboxSpecifier.inbox, false, null, cancellable)
            );
            if (response.status == Status.OK && !list_results.is_empty) {
                this.inbox = list_results[0];
                list_results.clear();
                debug("Using INBOX: %s", this.inbox.to_string());
            } else {
                throw new ImapError.INVALID("Unable to find INBOX");
            }

            // Try to determine what the connection's namespaces are
            if (this.capabilities.has_capability(Capabilities.NAMESPACE)) {
                response = yield send_command_async(
                    new NamespaceCommand(cancellable)
                );
                if (response.status != Status.OK) {
                    warning("NAMESPACE command failed");
                }
            }
            if (!this.personal_namespaces.is_empty) {
                debug(
                    "Default personal namespace: %s",
                    this.personal_namespaces[0].to_string()
                );
            } else {
                string? prefix = "";
                string? delim = this.inbox.delim;
                if (!this.inbox.attrs.contains(MailboxAttribute.NO_INFERIORS) &&
                    this.inbox.delim == ".") {
                    // We're probably on an ancient Cyrus install that
                    // doesn't support NAMESPACE, so assume they go in the inbox
                    prefix = this.inbox.mailbox.name + ".";
                }

                if (delim == null) {
                    // We still don't know what the delim is, so fetch
                    // it. In particular, uw-imap sends a null prefix
                    // for the inbox.
                    response = yield send_command_async(
                        new ListCommand(
                            new MailboxSpecifier(prefix),
                            false,
                            null,
                            cancellable
                        )
                    );
                    if (response.status == Status.OK && !list_results.is_empty) {
                        MailboxInformation list = list_results[0];
                        delim = list.delim;
                    } else {
                        throw new ImapError.INVALID("Unable to determine personal namespace delimiter");
                    }
                }

                this.personal_namespaces.add(new Namespace(prefix, delim));
                debug("Personal namespace not specified, guessed as: %s",
                      this.personal_namespaces[0].to_string());
            }
        } finally {
            disconnect(list_id);
        }
    }

    private uint on_login(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;

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

        uint new_state = State.AUTHORIZED;
        if (completion_response.status != OK) {
            debug("LOGIN failed: %s", completion_response.to_string());
            new_state = State.NOAUTH;
        }
        return new_state;
    }

    //
    // keepalives (nop idling to keep the session alive and to periodically receive notifications
    // of changes)
    //

    /**
     * Enables sending keep-alive commands for the sesion.
     *
     * Although keepalives can be enabled at any time, if they're
     * enabled and trigger sending a command prior to connection,
     * error signals may be fired.
     *
     * If values are negative or zero, keepalives will be disabled.
     * (This is not recommended.)
     */
    public void enable_keepalives(uint seconds_while_selected,
                                  uint seconds_while_unselected,
                                  uint seconds_while_selected_with_idle) {
        this.selected_keepalive_secs = seconds_while_selected;
        this.selected_with_idle_keepalive_secs = seconds_while_selected_with_idle;
        this.unselected_keepalive_secs = seconds_while_unselected;

        // schedule one now, although will be rescheduled if traffic
        // is received before it fires
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
     * Enables IMAP IDLE for the client session, if supported.
     *
     * If enabled, an IDLE command will be used for notification of
     * unsolicited server data whenever a mailbox is selected or
     * examined.  IDLE will only be used if ClientSession has seen a
     * CAPABILITY server data response with IDLE listed as a supported
     * extension.
     */
    public void enable_idle()
        throws GLib.Error {
        if (this.is_idle_supported) {
            switch (this.protocol_state) {
            case ProtocolState.AUTHORIZING:
            case ProtocolState.AUTHORIZED:
            case ProtocolState.SELECTED:
            case ProtocolState.SELECTING:
                this.cx.enable_idle_when_quiet(true);
                break;

            default:
                throw new ImapError.NOT_SUPPORTED(
                    "IMAP IDLE only supported in AUTHORIZED or SELECTED states"
                );
            }
        }
    }

    private void schedule_keepalive() {
        // if old one was scheduled, unschedule and schedule anew
        unschedule_keepalive();

        uint seconds;
        switch (this.protocol_state) {
            case ProtocolState.NOT_CONNECTED:
            case ProtocolState.CONNECTING:
                return;

            case ProtocolState.SELECTING:
            case ProtocolState.SELECTED:
                seconds = (this.cx.idle_when_quiet && this.is_idle_supported)
                    ? selected_with_idle_keepalive_secs
                    : selected_keepalive_secs;
            break;

            case ProtocolState.UNAUTHORIZED:
            case ProtocolState.AUTHORIZING:
            case ProtocolState.AUTHORIZED:
            case ProtocolState.CLOSING_MAILBOX:
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

        send_command_async.begin(
            new NoopCommand(null),
            on_keepalive_completed
        );
        debug("Sending keepalive...");

        // No need to reschedule keepalive, as the notification that the command was sent should
        // do that automatically

        return false;
    }

    private void on_keepalive_completed(Object? source, AsyncResult result) {
        try {
            send_command_async.end(result);
        } catch (GLib.Error err) {
            warning("Keepalive error: %s", err.message);
        }
    }

    //
    // send commands
    //

    public async StatusResponse send_command_async(Command cmd)
        throws GLib.Error {
        check_unsupported_send_command(cmd);

        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.SEND_CMD, null, params);

        if (params.err != null)
            throw params.err;

        assert(params.proceed);

        return yield submit_command(cmd);
    }

    public async Gee.Map<Command, StatusResponse>
        send_multiple_commands_async(Gee.Collection<Command> cmds,
                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (cmds.size == 0)
            throw new ImapError.INVALID("Must supply at least one command");

        foreach (Command cmd in cmds)
            check_unsupported_send_command(cmd);

        // only issue one event to the state machine for all commands; either all succeed or all fail
        MachineParams params = new MachineParams(Collection.first(cmds));
        fsm.issue(Event.SEND_CMD, null, params);

        if (params.err != null)
            throw params.err;

        assert(params.proceed);

        // Issue all at once using a single Nonblocking.Batch unless
        // the endpoint's max pipeline size is positive, if so use
        // multiple batches with a maximum size of that.

        uint max_batch_size = this.quirks.max_pipeline_batch_size;
        if (max_batch_size < 1) {
            max_batch_size = cmds.size;
        }

        Gee.Iterator<Command> cmd_remaining = cmds.iterator();
        Nonblocking.Batch? batch = null;
        Gee.Map<Command, StatusResponse> responses = new Gee.HashMap<Command, StatusResponse>();
        while (cmd_remaining.has_next()) {
            batch = new Nonblocking.Batch();
            while (cmd_remaining.has_next() && batch.size < max_batch_size) {
                cmd_remaining.next();
                batch.add(new SendCommandOperation(this, cmd_remaining.get()));
            }

            yield batch.execute_all_async(cancellable);
            batch.throw_first_exception();

            foreach (int id in batch.get_ids()) {
                SendCommandOperation op = (SendCommandOperation) batch.get_operation(id);
                responses.set(op.cmd, op.response);
            }
        }

        return responses;
    }

    private void check_unsupported_send_command(Command cmd) throws Error {
        // look for special commands that we wish to handle directly, as they affect the state
        // machine
        //
        // TODO: Convert commands into proper calls to avoid throwing an exception
        if (cmd.has_name(LoginCommand.NAME)
            || cmd.has_name(AuthenticateCommand.NAME)
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
                debug("Received unilateral BYE from server: %s",
                      status_response.to_string());

                // nothing more we can do; drop connection and report disconnect to user
                this.do_disconnect.begin(DisconnectReason.REMOTE_CLOSE);
                state = State.CLOSED;
            break;

            default:
                debug("Received error from server: %s",
                      status_response.to_string());
            break;
        }

        return state;
    }

    //
    // select/examine
    //

    public async StatusResponse select_async(MailboxSpecifier mailbox,
                                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        return yield select_examine_async(mailbox, true, cancellable);
    }

    public async StatusResponse examine_async(MailboxSpecifier mailbox,
                                              GLib.Cancellable? cancellable)
        throws GLib.Error {
        return yield select_examine_async(mailbox, false, cancellable);
    }

    public async StatusResponse select_examine_async(MailboxSpecifier mailbox,
                                                     bool is_select,
                                                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Ternary troubles
        Command cmd;
        if (is_select)
            cmd = new SelectCommand(mailbox, cancellable);
        else
            cmd = new ExamineCommand(mailbox, cancellable);

        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.SELECT, null, params);

        if (params.err != null)
            throw params.err;

        assert(params.proceed);

        return yield submit_command(cmd);
    }

    private uint on_select(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;

        if (!reserve_state_change_cmd(params, state, event))
            return state;

        return State.SELECTING;
    }

    private uint on_not_selected(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;

        params.err = new ImapError.INVALID("Can't close mailbox, not selected");

        return state;
    }

    private uint on_selecting_recv_completion(uint state, uint event, void *user, Object? object) {
        uint new_state = state;
        StatusResponse completion_response = (StatusResponse) object;

        Command? cmd = null;
        if (validate_state_change_cmd(completion_response, out cmd)) {
            switch (completion_response.status) {
            case Status.OK:
                if (cmd is SelectCommand) {
                    this.selected_mailbox = ((SelectCommand) cmd).mailbox;
                    this.selected_readonly = false;
                } else if (cmd is ExamineCommand) {
                    this.selected_mailbox = ((ExamineCommand) cmd).mailbox;
                    this.selected_readonly = true;
                }
                new_state = State.SELECTED;
                break;

            default:
                this.selected_mailbox = null;
                this.selected_readonly = false;
                new_state = State.AUTHORIZED;
                warning("SELECT/EXAMINE failed: %s",
                        completion_response.to_string());
                break;
            }
        }

        return new_state;
    }

    //
    // close mailbox
    //

    public async StatusResponse close_mailbox_async(GLib.Cancellable? cancellable)
        throws GLib.Error {
        CloseCommand cmd = new CloseCommand(cancellable);

        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.CLOSE_MAILBOX, null, params);

        if (params.err != null)
            throw params.err;

        return yield submit_command(cmd);
    }

    private uint on_close_mailbox(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;

        assert(params.cmd is CloseCommand);
        if (!reserve_state_change_cmd(params, state, event))
            return state;

        // returning to AUTHORIZED state, turn off IDLE
        this.cx.enable_idle_when_quiet(false);

        return State.CLOSING_MAILBOX;
    }

    private uint on_closing_recv_completion(uint state, uint event, void *user, Object? object) {
        StatusResponse completion_response = (StatusResponse) object;

        if (!validate_state_change_cmd(completion_response))
            return state;

        switch (completion_response.status) {
            case Status.OK:
                this.selected_mailbox = null;
                this.selected_readonly = false;
                return State.AUTHORIZED;

            default:
                warning("CLOSE failed: %s", completion_response.to_string());
                return State.SELECTED;
        }
    }

    //
    // logout
    //

    /**
     * Sends a logout command.
     *
     * If the connection is still available and the server still
     * responding, this will result in the connection being closed
     * gracefully. Thus unless an error occurs, {@link
     * disconnect_async} would not need to be called afterwards.
     */
    public async void logout_async(GLib.Cancellable? cancellable)
        throws GLib.Error {
        LogoutCommand cmd = new LogoutCommand(cancellable);

        MachineParams params = new MachineParams(cmd);
        fsm.issue(Event.LOGOUT, null, params);

        if (params.err != null)
            throw params.err;

        if (params.proceed) {
            yield submit_command(cmd);
            yield do_disconnect(DisconnectReason.LOCAL_CLOSE);
        }
    }

    private uint on_logout(uint state, uint event, void *user, Object? object) {
        MachineParams params = (MachineParams) object;

        assert(params.cmd is LogoutCommand);
        if (reserve_state_change_cmd(params, state, event)) {
            state = State.LOGOUT;
        }

        return state;
    }

    private uint on_logging_out_recv_status(uint state,
                                            uint event,
                                            void *user,
                                            Object? object) {
        StatusResponse status_response = (StatusResponse) object;

        switch (status_response.status) {
            case Status.OK:
                // some good-feeling text that doesn't need to be
                // handled when in this state
            break;

            case Status.BYE:
                // We're expecting this bye, but don't disconnect yet
                // since we'll do that when the command is complete
                debug("Received bye from server on logout: %s",
                      status_response.to_string());
            break;

            default:
                warning("Received error from server on logout: %s",
                        status_response.to_string());
            break;
        }

        return state;
    }

    private uint on_logging_out_recv_completion(uint state, uint event, void *user, Object? object) {
        StatusResponse completion_response = (StatusResponse) object;

        uint new_state = state;
        if (validate_state_change_cmd(completion_response)) {
            new_state = State.CLOSED;

            // Namespaces are only valid in AUTH and SELECTED states
            clear_namespaces();
        }
        return new_state;
    }

    //
    // disconnect
    //

    public async void disconnect_async(GLib.Cancellable? cancellable)
        throws GLib.Error {
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
        this.disconnected = DisconnectReason.LOCAL_CLOSE;

        if (disconnect_err != null)
            throw disconnect_err;
    }

    /** {@inheritDoc} */
    public string to_string() {
        string cx = ", " + (
            (this.cx != null) ? this.cx.to_string() : "not connected"
        );
        return Logging.Source.default_to_string(this, cx);
    }

    /** {@inheritDoc} */
    public Logging.State to_logging_state() {
        return (this.selected_mailbox == null)
            ? new Logging.State(
                this,
                this.fsm.get_state_string(fsm.state)
            )
            : new Logging.State(
                this,
                "%s:%s selected %s",
                this.fsm.get_state_string(fsm.state),
                this.selected_mailbox.to_string(),
                this.selected_readonly ? "RO" : "RW"
            );
    }

    /** Sets the connection's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    private async void do_disconnect(DisconnectReason reason) {
        this.disconnected = reason;

        try {
            yield this.cx.disconnect_async();
        } catch (GLib.Error err) {
            debug("IMAP disconnect failed: %s", err.message);
        }

        drop_connection();
    }

    //
    // error handling
    //

    // use different error handler when connecting because, if
    // connect_async() fails, there's no requirement for the user to
    // call disconnect_async() and clean up... this prevents leaving
    // the FSM in the CONNECTING state, causing an assertion when this
    // object is destroyed
    private uint on_connecting_send_recv_error(uint state,
                                               uint event,
                                               void *user,
                                               GLib.Object? object,
                                               GLib.Error? err) {
        debug(
            "Connecting send/recv error, dropping client connection: %s",
            err != null ? err.message : "(no error)"
        );
        fsm.do_post_transition(() => { drop_connection(); });
        return State.CLOSED;
    }

    private uint on_send_error(uint state, uint event, void *user, Object? object, Error? err) {
        if (err is IOError.CANCELLED) {
            return state;
        }

        debug("Send error, disconnecting: %s", err.message);
        this.do_disconnect.begin(DisconnectReason.LOCAL_ERROR);
        return State.CLOSED;
    }

    private uint on_recv_error(uint state,
                               uint event,
                               void *user,
                               GLib.Object? object,
                               GLib.Error? err) {
        debug(
            "Receive error, disconnecting: %s",
            (err != null) ? err.message : "(no error)"
        );
        this.do_disconnect.begin(DisconnectReason.REMOTE_ERROR);
        return State.CLOSED;
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

        debug("Dropped server response at %s: %s",
              fsm.get_event_issued_string(state, event),
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
        debug("Ignored transition: %s",
              fsm.get_event_issued_string(state, event));

        return state;
    }

    //
    // command submission
    //

    private async StatusResponse submit_command(Command cmd)
        throws GLib.Error {
        if (this.cx == null) {
            throw new ImapError.NOT_CONNECTED(
                "Not connected to %s", imap_endpoint.to_string()
            );
        }
        this.cx.send_command(cmd);

        // Once a command has been sent over the wire, it can't be
        // cancelled until a response is received, because the server
        // will send a response back anyway and so the command needs
        // to be around for it.
        yield cmd.wait_until_complete(null);

        // This won't be null since the Command.wait_until_complete
        // will throw an error if it is.
        return cmd.status;
    }

    //
    // network connection event handlers
    //

    private void on_network_send_error(Error err) {
        fsm.issue(Event.SEND_ERROR, null, null, err);
    }

    private void on_received_status_response(StatusResponse status_response) {
        // XXX Need to ignore emitted IDLE status responses. They are
        // emitted by ClientConnection because it doesn't make any
        // sense not to, and so they get logged by that class's
        // default handlers, but because they are snooped on here (and
        // even worse are used to push FSM transitions, rather relying
        // on the actual commands themselves), we need to check for
        // IDLE responses and ignore them.
        Command? command = this.cx.get_sent_command(status_response.tag);
        if (command == null || !(command is IdleCommand)) {
            // If a CAPABILITIES ResponseCode, decode and update
            // capabilities ...  some servers do this to prevent a
            // second round-trip
            ResponseCode? response_code = status_response.response_code;
            if (response_code != null) {
                try {
                    if (response_code.get_response_code_type().is_value(ResponseCodeType.CAPABILITY)) {
                        this.capabilities = response_code.get_capabilities(
                            this.capabilities.revision + 1
                        );
                        debug(
                            "%s set capabilities to: %s",
                            status_response.status.to_string(),
                            this.capabilities.to_string()
                        );
                    }
                } catch (GLib.Error err) {
                    warning(
                        "Unable to convert response code to capabilities: %s",
                        err.message
                    );
                }
            }

            // update state machine before notifying subscribers, who
            // may turn around and query ClientSession
            if (status_response.is_completion) {
                fsm.issue(Event.RECV_COMPLETION, null, status_response, null);
            } else {
                fsm.issue(Event.RECV_STATUS, null, status_response, null);
            }

            status_response_received(status_response);
        }
    }

    private void notify_received_data(ServerData server_data) throws ImapError {
        switch (server_data.server_data_type) {
            case ServerDataType.CAPABILITY:
                // update ClientSession capabilities before firing signal, so external signal
                // handlers that refer back to property aren't surprised
                this.capabilities = server_data.get_capabilities(
                    this.capabilities.revision + 1
                );
                debug(
                    "%s set capabilities to: %s",
                    server_data.server_data_type.to_string(),
                    this.capabilities.to_string()
                );
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

            case ServerDataType.NAMESPACE:
                // Clear namespaces before updating them, since if
                // they have changed the new ones take full
                // precedence.
                clear_namespaces();
                NamespaceResponse ns = server_data.get_namespace();
                update_namespaces(ns.personal, this.personal_namespaces);
                update_namespaces(ns.shared, this.shared_namespaces);
                update_namespaces(ns.user, this.user_namespaces);
            break;

            // TODO: LSUB
            case ServerDataType.LSUB:
            default:
                // do nothing
                debug("Not notifying of unhandled server data: %s",
                      server_data.to_string());
            break;
        }
    }

    private void clear_namespaces() {
        this.namespaces.clear();
        this.personal_namespaces.clear();
        this.shared_namespaces.clear();
        this.user_namespaces.clear();
    }

    private void update_namespaces(Gee.List<Namespace>? response,
                                   Gee.List<Namespace> list) {
        if (response != null) {
            foreach (Namespace ns in response) {
                list.add(ns);
                string prefix = ns.prefix;
                string? delim = ns.delim;
                if (delim != null && prefix.has_suffix(delim)) {
                    prefix = prefix.substring(0, prefix.length - delim.length);
                }
                this.namespaces.set(prefix, ns);
            }
        }
    }

    private void on_received_server_data(ServerData server_data) {
        // send ServerData to upper layers for processing and storage
        try {
            notify_received_data(server_data);
        } catch (ImapError ierr) {
            debug("Failure notifying of server data: %s %s",
                  server_data.to_string(),
                  ierr.message);
        }
    }

    private void on_received_bytes() {
        this.last_seen = GLib.get_real_time();

        // reschedule keepalive
        schedule_keepalive();
    }

    private void on_received_bad_response(RootParameters root, ImapError err) {
        debug("Received bad response %s: %s", root.to_string(), err.message);
        fsm.issue(Event.RECV_ERROR, null, null, err);
    }

    private void on_network_receive_failure(GLib.Error err) {
        fsm.issue(Event.RECV_ERROR, null, null, err);
    }

}
