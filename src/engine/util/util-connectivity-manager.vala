/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Keeps track of network connectivity changes for an endpoint.
 *
 * This class is a convenience API for the GIO NetworkMonitor. Since
 * when connecting and disconnecting from a network, multiple
 * network-changed signals may be sent, this class coalesces these as
 * best as possible so the rest of the engine is only notified once
 * when an endpoint becomes reachable, and once when it becomes
 * unreachable.
 *
 * Note this class is not thread safe and should only be invoked from
 * the main loop.
 */
public class Geary.ConnectivityManager : BaseObject {

	/** Determines if the managed endpoint is currently reachable. */
	public bool is_reachable { get; private set; default = false; }

    private Endpoint endpoint;

    private NetworkMonitor monitor;

	private Cancellable? existing_check = null;


    /**
     * Constructs a new manager for a specific endpoint.
     */
    public ConnectivityManager(Endpoint endpoint) {
		this.endpoint = endpoint;

        this.monitor = NetworkMonitor.get_default();
        this.monitor.network_changed.connect(on_network_changed);
    }

    ~ConnectivityManager() {
        this.monitor.network_changed.disconnect(on_network_changed);
    }

	/**
	 * Starts checking if the manager's endpoint is reachable.
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

		string endpoint = this.endpoint.to_string();
		bool is_reachable = this.is_reachable;
        try {
			debug("Checking if %s reachable...", endpoint);
            is_reachable = yield this.monitor.can_reach_async(
				this.endpoint.remote_address,
				cancellable
			);
        } catch (Error err) {
            if (err is IOError.NETWORK_UNREACHABLE &&
				this.monitor.network_available) {
				// If we get a network unreachable error, but the monitor
				// says there actually is a network available, we may be
				// running in a Flatpak and hitting Bug 777706. If so,
				// just assume the service is reachable is for now. :(
				is_reachable = true;
				debug("Assuming %s is reachable, despite network unavailability",
					  endpoint);
			} else if (!(err is IOError.CANCELLED)) {
				// Service is unreachable
				debug("Error checking %s reachable, treating as unreachable: %s",
						endpoint, err.message);
				is_reachable = false;
			}
        } finally {
			if (!cancellable.is_cancelled()) {
				set_reachable(is_reachable);
			}
            this.existing_check = null;
        }
    }

	/**
	 * Cancels any running reachability check, if any.
	 */
    public void cancel_check() {
		if (this.existing_check != null) {
			this.existing_check.cancel();
			this.existing_check = null;
		}
	}

    private void on_network_changed(bool some_available) {
        // Always check if reachable because IMAP server could be on
        // localhost.  (This is a Linux program, after all...)
		debug("Network changed: %s",
			  some_available ? "some available" : "none available");
		if (some_available) {
			// Some hosts may have dropped out despite network being
			// still xavailable, so need to check again
			this.check_reachable.begin();
		} else {
			// None available, so definitely not reachable
			set_reachable(false);
		}
    }

	private inline void set_reachable(bool reachable) {
		// Coalesce changes to is_reachable, since Vala <= 0.34 always
		// fires notify signals on set, even if the value doesn't
		// change. 0.36 fixes that, so pull this out when we can
		// depend on that as a minimum.
		if (this.is_reachable != reachable) {
			this.is_reachable = reachable;
		}
	}

}
