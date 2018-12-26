/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Manages client connections to a specific network service.
 *
 * Derived classes are used by accounts to manage client connections
 * to a specific network service, such as IMAP or SMTP. This class
 * does connect to the service itself, rather manages the
 * configuration and life-cycle of client sessions that do connect to
 * the service.
 */
public abstract class Geary.ClientService : BaseObject {


    /**
     * The service's account.
     */
    public AccountInformation account { get; private set; }

    /**
     * The configuration for the service.
     */
    public ServiceInformation configuration { get; private set; }

    /**
     * The network endpoint the service will connect to.
     */
    public Endpoint remote { get; private set; }

    /** Determines if this manager has been started. */
    public bool is_running { get; protected set; default = false; }


    protected ClientService(AccountInformation account,
                            ServiceInformation configuration,
                            Endpoint remote) {
        this.account = account;
        this.configuration = configuration;
        this.remote = remote;
    }

    /**
     * Updates the service's network endpoint and restarts if needed.
     *
     * The service will be restarted if it is already running, and if
     * so will be stopped before the old endpoint is replaced by the
     * new one, then started again.
     */
    public async void set_endpoint_restart(Endpoint endpoint,
                                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (this.remote != null) {
            this.remote.untrusted_host.disconnect(on_untrusted_host);
        }

        bool do_restart = this.is_running;
        if (do_restart) {
            yield stop(cancellable);
        }

        this.remote = remote;
        this.remote.untrusted_host.connect(on_untrusted_host);

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


    private void on_untrusted_host(TlsNegotiationMethod method,
                                   GLib.TlsConnection cx) {
        this.account.untrusted_host(this.configuration, method, cx);
    }

}
