/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Manages client connections to a specific network service.
 *
 * Client service object are used by accounts to manage client
 * connections to a specific network service, such as IMAP or SMTP
 * services. This abstract class does not connect to the service
 * itself, rather manages the configuration, status tracking, and
 * life-cycle of concrete implementations.
 */
public abstract class Geary.ClientService : BaseObject, Logging.Source {


    // Keep the unreachable timeout short so that when the connection
    // actually goes down connections get pulled down ASAP. Keep the
    // reachable timeout higher to avoid trying to reconnect
    // immediately on notification of being reachable, which can be a
    // bit bouncy
    private const int BECAME_REACHABLE_TIMEOUT_SEC = 3;
    private const int BECAME_UNREACHABLE_TIMEOUT_SEC = 1;

    private const string LOGIND_DBUS_NAME = "org.freedesktop.login1";
    private const string LOGIND_DBUS_PATH = "/org/freedesktop/login1";
    private const string LOGIND_DBUS_INTERFACE = "org.freedesktop.login1.Manager";

    /**
     * Denotes the service's current status.
     *
     * @see ClientService.current_status
     * @see Account.current_status
     */
    public enum Status {

        /**
         * The service status is currently unknown.
         *
         * This is the initial state, and will only change after the
         * service has performed initial connectivity testing and/or
         * successfully connected to the remote host.
         */
        UNKNOWN,

        /**
         * The service is currently unreachable.
         *
         * This typically indicates the local computer is offline. The
         * service will attempt to determine if the remote host is
         * reachable once the service has been started. If determined
         * to be reachable, the service will attempt to connect to the
         * host, otherwise it will be marked as unreachable.
         */
        UNREACHABLE,

        /**
         * The service is connected and working normally.
         *
         * A connection to the remote host has been established and is
         * operating normally.
         */
        CONNECTED,

        /**
         * A network problem occurred connecting to the service.
         *
         * This is caused by DNS lookup failures, connectivity
         * failures, the service rejecting the connection due to
         * connection limits, or the service configuration being out
         * of date.
         *
         * The {@link connection_error} signal will be fired with an
         * error (if any), and an attempt to re-connect will be made
         * when the connectivity manager indicates the network has
         * changed. It may also require manual intervention to update
         * the service's configuration to successfully re-connect,
         * however.
         */
        CONNECTION_FAILED,

        /**
         * The service's credentials were rejected by the remote service.
         *
         * The {@link AccountInformation.authentication_failure}
         * signal on the service's account configuration will be fired
         * and no more connection attempts will be made until the
         * service is restarted.
         */
        AUTHENTICATION_FAILED,

        /**
         * The remote service's TLS certificate was rejected.
         *
         * The {@link AccountInformation.untrusted_host} signal on the
         * service's account configuration will be fired and no more
         * connection attempts will be made until the service is
         * restarted.
         */
        TLS_VALIDATION_FAILED,

        /**
         * A general problem occurred with the remote service.
         *
         * A network connection was successfully established, but some
         * problem other than authentication or TLS certificate
         * validation has prevented a successful connection. This may
         * be because of an unsupported protocol version or other
         * general incompatibility.
         *
         * The {@link unrecoverable_error} signal will be fired with
         * an error (if any), and no more connection attempts will be
         * made until the service is restarted.
         */
        UNRECOVERABLE_ERROR;


        /**
         * Determines if re-connection should be attempted from this state.
         *
         * If the service is in this state, it will automatically
         * attempt to reconnect when connectivity changes have been
         * detected.
         */
        public bool automatically_reconnect() {
            return (
                this == UNKNOWN ||
                this == UNREACHABLE ||
                this == CONNECTED ||
                this == CONNECTION_FAILED
            );
        }

        /**
         * Determines the current status is an error condition.
         *
         * Returns true if not offline or connected.
         */
        public bool is_error() {
            return (
                this != UNKNOWN &&
                this != UNREACHABLE &&
                this != CONNECTED
            );
        }

        public string to_value() {
            return ObjectUtils.to_enum_nick<Status>(typeof(Status), this);
        }

    }


    /**
     * Fired when the service encounters a connection error.
     *
     * @see Status.CONNECTION_FAILED
     */
    public signal void connection_error(ErrorContext err);

    /**
     * Fired when the service encounters an unrecoverable error.
     *
     * @see Status.UNRECOVERABLE_ERROR
     */
    public signal void unrecoverable_error(ErrorContext err);


    /** The service's account. */
    public AccountInformation account { get; private set; }

    /** The configuration for the service. */
    public ServiceInformation configuration { get; private set; }

    /**
     * The service's current status.
     *
     * The current state of certain aspects of the service
     * (e.g. online/offline state may not be fully known, and hence
     * the value of this property reflects the engine's current
     * understanding of the service's status, not necessarily that of
     * actual reality.
     *
     * The initial value for this property is {@link Status.UNKNOWN}.
     *
     * @see Account.current_status
     */
    public Status current_status { get; protected set; default = UNKNOWN; }

    /** The network endpoint the service will connect to. */
    public Endpoint remote { get; private set; }

    /** Determines if this service has been started. */
    public bool is_running { get; private set; default = false; }

    // Since the connectivity manager can flip-flop rapidly, introduce
    // some hysteresis on connectivity changes to smooth out the
    // transitions.
    private TimeoutManager became_reachable_timer;
    private TimeoutManager became_unreachable_timer;

    private DBusProxy logind_proxy;

    /** The last reported error, if any. */
    public ErrorContext? last_error { get; private set; default = null; }

    /** {@inheritDoc} */
    // XXX see GNOME/vala#119 for why this is necessary
    public virtual string logging_domain {
        get { return Logging.DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;


    protected ClientService(AccountInformation account,
                            ServiceInformation configuration,
                            Endpoint remote) {
        this.account = account;
        this.configuration = configuration;
        this.remote = remote;

        this.became_reachable_timer = new TimeoutManager.seconds(
            BECAME_REACHABLE_TIMEOUT_SEC, became_reachable
        );
        this.became_unreachable_timer = new TimeoutManager.seconds(
            BECAME_UNREACHABLE_TIMEOUT_SEC, became_unreachable
        );

        try {
            this.logind_proxy = new DBusProxy.for_bus_sync(
                BusType.SYSTEM,
                DBusProxyFlags.NONE,
                null,
                LOGIND_DBUS_NAME,
                LOGIND_DBUS_PATH,
                LOGIND_DBUS_INTERFACE,
                null
            );
            this.logind_proxy.g_signal.connect(this.on_logind_signal);
        } catch (GLib.Error err) {
            debug("Failed to connect logind bus: %s", err.message);
        }

        connect_handlers();

        this.notify["is-running"].connect(on_running_notify);
        this.notify["current-status"].connect(on_current_status_notify);
    }

    ~ClientService() {
        disconnect_handlers();
    }

    /**
     * Updates the configuration for the service.
     *
     * The service will be restarted if it is already running, and if
     * so will be stopped before the old configuration and endpoint is
     * replaced by the new one, then started again.
     */
    public async void update_configuration(ServiceInformation configuration,
                                           Endpoint remote,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        disconnect_handlers();

        bool do_restart = this.is_running;
        if (do_restart) {
            yield stop(cancellable);
        }

        this.configuration = configuration;
        this.remote = remote;
        connect_handlers();

        if (do_restart) {
            yield start(cancellable);
        }
    }

    /**
     * Starts the service running.
     *
     * This may cause the manager to establish connections to the
     * network service.
     */
    public abstract async void start(GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Stops the service running.
     *
     * Any existing connections to the network service will be closed.
     */
    public abstract async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Starts the service, stopping it first if running.
     *
     * An error will be thrown if the service could not be stopped or
     * could not be started again. If an error is thrown while
     * stopping the service, no attempt will be made to start it
     * again.
     */
    public async void restart(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (this.is_running) {
            yield stop(cancellable);
        }

        yield start(cancellable);
    }

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(this, this.configuration.protocol.to_value());
    }

    /** Sets the service's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    /**
     * Called when the network service has become reachable.
     *
     * Derived classes may wish to attempt to establish a network
     * connection to the remote service when this is called.
     */
    protected abstract void became_reachable();

    /**
     * Called when the network service has become unreachable.
     *
     * Derived classes should close any network connections that are
     * being established, or have been established with remote
     * service.
     */
    protected abstract void became_unreachable();

    /**
     * Notifies the network service has been started.
     *
     * Derived classes must call this when they consider the service
     * to has been successfully started, to update service status and
     * start reachable checking.
     */
    protected void notify_started() {
        this.is_running = true;
        if (this.remote.connectivity.is_reachable.is_certain()) {
            became_reachable();
        } else if (this.remote.connectivity.is_reachable.is_impossible()) {
            this.current_status = UNREACHABLE;
        } else {
            this.remote.connectivity.check_reachable.begin();
        }
    }

    /**
     * Notifies when the network service has been stopped.
     *
     * Derived classes must call this before stopping the service to
     * update service status and cancel any pending reachable checks.
     */
    protected void notify_stopped() {
        this.is_running = false;
        this.current_status = UNKNOWN;
        this.became_reachable_timer.reset();
        this.became_unreachable_timer.reset();
    }

    /**
     * Notifies that the service has successfully connected.
     *
     * Derived classes should call this when a connection to the
     * network service has been successfully negotiated and appears to
     * be operating normally.
     */
    protected void notify_connected() {
        this.current_status = CONNECTED;
    }

    /**
     * Notifies that a connection error occurred.
     *
     * Derived classes should call this when a connection to the
     * network service encountered some network error other than a
     * login failure or TLS certificate validation error.
     */
    protected void notify_connection_failed(ErrorContext? error) {
        // Set the error first so it is up to date when any
        // current-status notify handlers fire
        this.last_error = error;
        this.current_status = CONNECTION_FAILED;
        connection_error(error);
        // Network error, so try to connect again
        on_connectivity_change();
    }

    /**
     * Notifies that an authentication failure has occurred.
     *
     * Derived classes should call this when they have detected that
     * authentication has failed because the service rejected the
     * supplied credentials, but not when login failed for other
     * reasons (for example, connection limits being reached, service
     * temporarily unavailable, etc).
     */
    protected void notify_authentication_failed() {
        this.current_status = AUTHENTICATION_FAILED;
        this.account.authentication_failure(this.configuration);
    }

    /**
     * Notifies that an unrecoverable error has occurred.
     *
     * Derived classes should call this when they have detected that
     * some unrecoverable error has occurred when connecting to the
     * service, such as an unsupported protocol or version.
     */
    protected void notify_unrecoverable_error(ErrorContext error) {
        // Set the error first so it is up to date when any
        // current-status notify handlers fire
        this.last_error = error;
        this.current_status = UNRECOVERABLE_ERROR;
        unrecoverable_error(error);
    }

    private void connect_handlers() {
        this.remote.connectivity.notify["is-reachable"].connect(
            on_connectivity_change
        );
        this.remote.connectivity.remote_error_reported.connect(
            on_connectivity_error
        );
        this.remote.untrusted_host.connect(on_untrusted_host);
    }

    private void disconnect_handlers() {
        this.remote.connectivity.notify["is-reachable"].disconnect(
            on_connectivity_change
        );
        this.remote.connectivity.remote_error_reported.disconnect(
            on_connectivity_error
        );
        this.remote.untrusted_host.disconnect(on_untrusted_host);
    }

    private void on_running_notify() {
        debug(this.is_running ? "Started" : "Stopped");
    }

    private void on_current_status_notify() {
        debug("Status changed to: %s", this.current_status.to_value());
    }

    private void on_connectivity_change() {
        if (this.is_running && this.current_status.automatically_reconnect()) {
            if (this.remote.connectivity.is_reachable.is_certain()) {
                this.became_reachable_timer.start();
                this.became_unreachable_timer.reset();
            } else {
                this.current_status = UNREACHABLE;
                this.became_unreachable_timer.start();
                this.became_reachable_timer.reset();
            }
        }
    }

    private void on_connectivity_error(Error error) {
        if (this.is_running) {
            this.became_reachable_timer.reset();
            this.became_unreachable_timer.reset();
            // Since there was an error determining if the service was
            // reachable, assume it is no longer reachable.
            became_unreachable();
            notify_connection_failed(new ErrorContext(error));
        }
    }

    private void on_untrusted_host(Endpoint remote,
                                   GLib.TlsConnection cx) {
        if (this.is_running) {
            this.current_status = TLS_VALIDATION_FAILED;
            this.became_reachable_timer.reset();
            this.became_unreachable_timer.reset();
            // Since the host is not trusted, it should not be
            // considered reachable.
            became_unreachable();
            this.account.untrusted_host(this.configuration, remote, cx);
        }
    }

    private void on_logind_signal(DBusProxy logind_proxy, string? sender_name,
                                  string signal_name, Variant parameters)  {
        if (signal_name != "PrepareForSleep") {
            return;
        }

        bool about_to_suspend = parameters.get_child_value(0).get_boolean();
        if (about_to_suspend) {
            this.stop.begin();
        } else {
            this.start.begin();
        }
    }
}
