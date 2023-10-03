/*
 * Copyright 2017-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Keeps track of network connectivity changes for a network endpoint.
 *
 * This class is a convenience API for the GIO NetworkMonitor. Since
 * when connecting and disconnecting from a network, multiple
 * network-changed signals may be sent, this class coalesces these as
 * best as possible so the rest of the engine is only notified once
 * when a remote becomes reachable, and once when it becomes
 * unreachable.
 *
 * Note this class is not thread safe and should only be invoked from
 * the main loop.
 */
public class Geary.ConnectivityManager : BaseObject {

    private const uint CHECK_QUIESCENCE = 60 * 1000;
    private const uint CHECK_SOON = 1000;


    /** The endpoint being monitored. */
    public GLib.SocketConnectable remote { get; private set; default = null; }

    /** Determines if the managed endpoint is currently reachable. */
    public Trillian is_reachable {
        get; private set; default = Geary.Trillian.UNKNOWN;
    }

    /**
     * Determines if the remote endpoint could be resolved.
     *
     * This will become certain if the remote becomes reachable, and
     * will become impossible if a fatal error is reported.
     */
    public Trillian is_valid {
        get; private set; default = Geary.Trillian.UNKNOWN;
    }

    private NetworkMonitor monitor;

    private Cancellable? existing_check = null;

    private TimeoutManager delayed_check;


    /**
     * Fired when a fatal error was reported checking the remote.
     *
     * This is typically caused by an an authoritative DNS name not
     * found error, but may be anything else that indicates that the
     * remote will be unusable as-is without some kind of user or
     * server administrator intervention.
     */
    public signal void remote_error_reported(Error error);


    /**
     * Constructs a new manager for a specific remote.
     */
    public ConnectivityManager(GLib.SocketConnectable remote) {
        this.remote = remote;

        this.monitor = NetworkMonitor.get_default();
        this.monitor.network_changed.connect(on_network_changed);

        this.delayed_check = new TimeoutManager(
            () => { this.check_reachable.begin(); }
        );
    }

    ~ConnectivityManager() {
        this.monitor.network_changed.disconnect(on_network_changed);
    }

    /**
     * Starts checking if the manager's remote is reachable.
     *
     * This will cancel any existing check, and start a new one
     * running, updating the `is_reachable` property on completion.
     */
    public async void check_reachable(bool force_notify=false) {
        if (force_notify) {
            this.is_reachable = Geary.Trillian.UNKNOWN;
        }
        if (this.existing_check != null) {
            this.existing_check.cancel();
        }
        Cancellable cancellable = new Cancellable();
        this.existing_check = cancellable;

        string endpoint = this.remote.to_string();
        bool is_reachable = false;
        try {
            // Check first, and ask questions only if an error occurs,
            // because if we can connect, then we can connect.
            debug("Checking if %s reachable...", endpoint);
            SocketClient client = new SocketClient();
            // 5 seconds
            client.set_timeout(5);
            SocketConnection conn = yield client.connect_async(
                this.remote, cancellable
            );
            is_reachable = true;
        } catch (GLib.IOError.CANCELLED err) {
            // User cancelled, so leave as unreachable
        } catch (GLib.Error err) {
            debug("Checking %s reachable: %s", endpoint, err.message);
        } finally {
            if (!cancellable.is_cancelled()) {
                if (is_reachable) {
                    debug("%s reachable.", endpoint);
                } else {
                    debug("%s not reachable.", endpoint);
                }
                set_reachable(is_reachable);

                // Kick off another delayed check in case the network
                // changes without the monitor noticing.
                this.delayed_check.start_ms(CHECK_QUIESCENCE);
            }
            this.existing_check = null;
        }
    }

    /**
     * Cancels any running or future reachability check, if any.
     */
    public void cancel_check() {
        if (this.existing_check != null) {
            this.existing_check.cancel();
            this.existing_check = null;
        }
        this.delayed_check.reset();
    }

    private void on_network_changed(bool some_available) {
        // Always check if reachable because IMAP server could be on
        // localhost.  (This is a Linux program, after all...)
        debug("Network changed: %s",
              some_available ? "some available" : "none available");

        cancel_check();
        if (some_available) {
            this.delayed_check.start_ms(CHECK_SOON);
        } else {
            // None available, so definitely not reachable.
            set_reachable(false);
        }
    }

    private inline void set_reachable(bool reachable) {
        // Coalesce changes to is_reachable, since Vala <= 0.34 always
        // fires notify signals on set, even if the value doesn't
        // change. 0.36 fixes that, so pull this test out when we can
        // depend on that as a minimum.
        if ((reachable && !this.is_reachable.is_certain()) ||
            (!reachable && !this.is_reachable.is_impossible())) {
            debug("Remote %s became %s",
                  this.remote.to_string(), reachable ? "reachable" : "unreachable");
            this.is_reachable = reachable ? Trillian.TRUE : Trillian.FALSE;
        }

        // We only work out if the name is valid (or becomes valid
        // again) if the remote becomes reachable.
        if (reachable && this.is_valid.is_uncertain()) {
            this.is_valid = Trillian.TRUE;
        }

    }

    private inline void set_invalid() {
        // Coalesce changes to is_reachable, since Vala <= 0.34 always
        // fires notify signals on set, even if the value doesn't
        // change. 0.36 fixes that, so pull this method out when we can
        // depend on that as a minimum.
        if (this.is_valid != Trillian.FALSE) {
            this.is_valid = Trillian.FALSE;
        }
    }

    private bool is_local_address() {
        GLib.NetworkAddress? name = this.remote as GLib.NetworkAddress;
        if (name != null) {
            return (
                name.hostname == "localhost" ||
                name.hostname.has_prefix("localhost.") ||
                name.hostname == "127.0.0.1" ||
                name.hostname == "::1"
            );
        }

        GLib.InetSocketAddress? inet = this.remote as GLib.InetSocketAddress;
        if (inet != null) {
            return (
                inet.address.is_loopback ||
                inet.address.is_link_local
            );
        }

        return false;
    }

}
