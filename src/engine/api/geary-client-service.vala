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
public abstract class Geary.ClientService : BaseObject {


    private const int BECAME_REACHABLE_TIMEOUT_SEC = 1;
    private const int BECAME_UNREACHABLE_TIMEOUT_SEC = 3;


    /**
     * Denotes the service's current status.
     *
     * @see ClientService.current_status
     */
    public enum Status {

        /**
         * The service is currently offline.
         *
         * This is the initial state, and will only change after
         * having successfully connected to the remote service. An
         * attempt to connect will be made when the connectivity
         * manager indicates the network has changed.
         */
        OFFLINE,

        /** A connection has been established and is operating normally. */
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
                this == OFFLINE ||
                this == CONNECTED ||
                this == CONNECTION_FAILED
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
    public signal void connection_error(GLib.Error? err);

    /**
     * Fired when the service encounters an unrecoverable error.
     *
     * @see Status.UNRECOVERABLE_ERROR
     */
    public signal void unrecoverable_error(GLib.Error? err);


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
     * understanding of the service's status, not necessarily reality.
     */
    public Status current_status { get; protected set; default = OFFLINE; }

    /** The network endpoint the service will connect to. */
    public Endpoint remote { get; private set; }

    /** Determines if this service has been started. */
    public bool is_running { get; private set; default = false; }

    // Since the connectivity manager can flip-flop rapidly, introduce
    // some hysteresis on connectivity changes to smooth out the
    // transitions.
    private TimeoutManager became_reachable_timer;
    private TimeoutManager became_unreachable_timer;


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

        connect_handlers();

        this.notify["running"].connect(on_running_notify);
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
     * Starts the service manager running.
     *
     * This may cause the manager to establish connections to the
     * network service.
     */
    public abstract async void start(GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Stops the service manager running.
     *
     * Any existing connections to the network service will be closed.
     */
    public abstract async void stop(GLib.Cancellable? cancellable = null)
        throws GLib.Error;

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
        this.current_status = OFFLINE;
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
    protected void notify_connection_failed(GLib.Error? err) {
        this.current_status = CONNECTION_FAILED;
        connection_error(err);
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
    }

    /**
     * Notifies that an unrecoverable error has occurred.
     *
     * Derived classes should call this when they have detected that
     * some unrecoverable error has occurred when connecting to the
     * service, such as an unsupported protocol or version.
     */
    protected void notify_unrecoverable_error(GLib.Error? err) {
        this.current_status = UNRECOVERABLE_ERROR;
        unrecoverable_error(err);
    }

    private void connect_handlers() {
		this.remote.connectivity.notify["is-reachable"].connect(
            on_connectivity_change
        );
        this.remote.connectivity.address_error_reported.connect(
            on_connectivity_error
        );
        this.remote.untrusted_host.connect(on_untrusted_host);
    }

    private void disconnect_handlers() {
		this.remote.connectivity.notify["is-reachable"].disconnect(
            on_connectivity_change
        );
        this.remote.connectivity.address_error_reported.disconnect(
            on_connectivity_error
        );
        this.remote.untrusted_host.disconnect(on_untrusted_host);
    }

    private void on_running_notify() {
        debug(this.is_running ? "started" : "stopped");
    }

    private void on_current_status_notify() {
        debug(this.current_status.to_value());
    }

	private void on_connectivity_change() {
        if (this.is_running && this.current_status.automatically_reconnect()) {
            if (this.remote.connectivity.is_reachable.is_certain()) {
                this.became_reachable_timer.start();
                this.became_unreachable_timer.reset();
            } else {
                this.current_status = OFFLINE;
                this.became_unreachable_timer.start();
                this.became_reachable_timer.reset();
            }
        }
	}

	private void on_connectivity_error(Error error) {
        if (this.is_running) {
            this.current_status = CONNECTION_FAILED;
            this.became_reachable_timer.reset();
            this.became_unreachable_timer.reset();
            became_unreachable();
        }
	}

    private void on_untrusted_host(Geary.TlsNegotiationMethod method,
                                   GLib.TlsConnection cx) {
        if (this.is_running) {
            this.current_status = TLS_VALIDATION_FAILED;
            this.became_reachable_timer.reset();
            this.became_unreachable_timer.reset();
            became_unreachable();
            this.account.untrusted_host(this.configuration, method, cx);
        }
    }

}
