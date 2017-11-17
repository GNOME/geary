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


    private const uint CHECK_QUIESCENCE_MS = 60 * 1000;


	/** Determines if the managed endpoint is currently reachable. */
	public bool is_reachable { get; private set; default = false; }

    // Weak to avoid a circular ref with the endpoint
    private weak Endpoint endpoint;

    private NetworkMonitor monitor;

	private Cancellable? existing_check = null;

    // Wall time the next already-connected check should not occur before
    private int64 next_check = 0;

    private TimeoutManager delayed_check;


    /**
     * Constructs a new manager for a specific endpoint.
     */
    public ConnectivityManager(Endpoint endpoint) {
		this.endpoint = endpoint;

        this.monitor = NetworkMonitor.get_default();
        this.monitor.network_changed.connect(on_network_changed);

        this.delayed_check = new TimeoutManager.seconds(
            CHECK_QUIESCENCE_MS, () => { this.check_reachable.begin(); }
        );
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
            this.next_check = get_real_time() + CHECK_QUIESCENCE_MS;
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
            if (!this.is_reachable ||
                this.existing_check != null ||
                this.next_check <= get_real_time()) {
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
		// change. 0.36 fixes that, so pull this out when we can
		// depend on that as a minimum.
		if (this.is_reachable != reachable) {
            debug("Host %s became %s",
                  this.endpoint.to_string(), reachable ? "reachable" : "unreachable");
			this.is_reachable = reachable;
		}
	}

}
