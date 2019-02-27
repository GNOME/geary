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

    private const uint CHECK_QUIESCENCE_MS = 60 * 1000;


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

    // Wall time the next already-connected check should not occur before
    private int64 next_check = 0;

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

        this.delayed_check = new TimeoutManager.seconds(
            // Don't use the milliseconds ctor since we don't want
            // high-frequency timing.
            CHECK_QUIESCENCE_MS / 1000,
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
    public async void check_reachable() {
        // We use a cancellable here as a guard instead of a boolean
        // "is_checking" var since when a series of checks are
        // requested in quick succession (as is the case when
        // e.g. connecting or disconnecting from a network), the
        // result of the *last* check is authoritative, not the first
        // one.
        cancel_check();

        Cancellable cancellable = new Cancellable();
        this.existing_check = cancellable;

        string endpoint = this.remote.to_string();
        bool is_reachable = false;
        try {
            // Check first, and ask questions only if an error occurs,
            // because if we can connect, then we can connect.
            debug("Checking if %s reachable...", endpoint);
            is_reachable = yield this.monitor.can_reach_async(
                this.remote, cancellable
            );
            this.next_check = (
                GLib.get_real_time() + (CHECK_QUIESCENCE_MS * 1000)
            );
        } catch (GLib.IOError.CANCELLED err) {
            // User cancelled, so leave as unreachable
        } catch (GLib.DBusError err) {
            // Running under Flatpak can cause a DBus error if the
            // portal is malfunctioning (e.g. Geary #97 & #82 and
            // xdg-desktop-portal #208). We must treat this as
            // reachable so we make a connection attempt, otherwise it
            // will never happen.
            debug("DBus error checking %s reachable, treating as reachable: %s",
                  endpoint, err.message);
            is_reachable = true;
        } catch (GLib.ResolverError.TEMPORARY_FAILURE err) {
            // Host name could not be resolved since name servers
            // could not be reached, so treat as being offline.
            debug("Transient error checking %s reachable, treating offline: %s",
                  endpoint, err.message);
        } catch (GLib.Error err) {
            if (err is IOError.NETWORK_UNREACHABLE &&
                this.monitor.network_available) {
                // If we get a network unreachable error, but the monitor
                // says there actually is a network available, we may be
                // running in a Flatpak and hitting Bug 777706. If so,
                // just assume the service is reachable is for now. :(
                // Pull this put once xdg-desktop-portal 1.x is widely
                // installed.
                debug("Assuming %s is reachable, despite network unavailability",
                      endpoint);
                is_reachable = true;
            } else {
                // The monitor threw an error, but only notify if it
                // looks like we *should* be able to connect
                // (i.e. have full network connectivity, or are
                // connecting to a local service), so we don't
                // needlessly hassle the user with expected error
                // messages.
                GLib.NetworkConnectivity connectivity = this.monitor.connectivity;
                if (connectivity == FULL ||
                    (connectivity == LOCAL && is_local_address())) {
                    debug("Error checking %s [%s] reachable, treating unreachable: %s",
                          endpoint, connectivity.to_string(), err.message);
                    set_invalid();
                    remote_error_reported(err);
                } else {
                    debug("Error checking %s [%s] reachable, treating offline: %s",
                          endpoint, connectivity.to_string(), err.message);
                }
            }
        } finally {
            if (!cancellable.is_cancelled()) {
                set_reachable(is_reachable);

                // Kick off another delayed check in case the network
                // changes without the monitor noticing.
                this.delayed_check.start();
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
        if (some_available) {
            // Some networks may have dropped out despite some being
            // still available, so need to check again. Only run the
            // check if we are either currently:
            //
            // 1. Unreachable
            // 2. An existing check is already running (i.e. the
            //    network configuration is changing)
            // 3. Reachable, and a check hasn't been run recently
            //
            // Otherwise, schedule a delayed check to work around the
            // issue in Bug 776042.
            if (this.is_reachable.is_uncertain() ||
                this.existing_check != null ||
                this.next_check <= GLib.get_real_time()) {
                this.check_reachable.begin();
            } else if (!this.delayed_check.is_running) {
                this.delayed_check.start();
            }
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
