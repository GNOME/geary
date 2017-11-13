/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Keeps track of network connectivity changes for a network address.
 *
 * This class is a convenience API for the GIO NetworkMonitor. Since
 * when connecting and disconnecting from a network, multiple
 * network-changed signals may be sent, this class coalesces these as
 * best as possible so the rest of the engine is only notified once
 * when an address becomes reachable, and once when it becomes
 * unreachable.
 *
 * Note this class is not thread safe and should only be invoked from
 * the main loop.
 */
public class Geary.ConnectivityManager : BaseObject {

    /** The address being monitored. */
    public NetworkAddress address { get; private set; default = null; }

	/** Determines if the managed address is currently reachable. */
	public Trillian is_reachable { get; private set; default = Geary.Trillian.UNKNOWN; }

	/**
     * Determines if a the address's network address name is valid.
     *
     * This will become certain if the address becomes reachable, and
     * will become impossible if a fatal address error is reported.
     */
	public Trillian is_valid { get; private set; default = Geary.Trillian.UNKNOWN; }

    private NetworkMonitor monitor;

	private Cancellable? existing_check = null;


    /**
     * Fired when a fatal error was reported checking the address.
     *
     * This is typically caused by an an authoritative DNS name not
     * found error, but may be anything else that indicates that the
     * address will be unusable as-is without some kind of user or
     * server administrator intervention.
     */
    public signal void address_error_reported(Error error);


    /**
     * Constructs a new manager for a specific address.
     */
    public ConnectivityManager(NetworkAddress address) {
		this.address = address;

        this.monitor = NetworkMonitor.get_default();
        this.monitor.network_changed.connect(on_network_changed);
    }

    ~ConnectivityManager() {
        this.monitor.network_changed.disconnect(on_network_changed);
    }

	/**
     * Starts checking if the manager's address is reachable.
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

        string endpoint = to_address_string();
		bool is_reachable = false;
        try {
			debug("Checking if %s reachable...", endpoint);
            is_reachable = yield this.monitor.can_reach_async(this.address, cancellable);
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
			} else if (err is ResolverError.TEMPORARY_FAILURE) {
				// This often happens when networking is coming back
				// online, may because the interface is up but has not
				// been assigned an address yet? Since we should get
				// another network change when the interface is
				// configured, just ignore it.
				debug("Ignoring: %s", err.message);
			} else if (!(err is IOError.CANCELLED)) {
				// Service is unreachable
				debug("Error checking %s reachable, treating as unreachable: %s",
                      endpoint, err.message);
				set_invalid();
                address_error_reported(err);
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
		// change. 0.36 fixes that, so pull this test out when we can
		// depend on that as a minimum.
		if ((reachable && !this.is_reachable.is_certain()) ||
            (!reachable && !this.is_reachable.is_impossible())) {
            debug("Host %s became %s",
                  this.address.to_string(), reachable ? "reachable" : "unreachable");
			this.is_reachable = reachable ? Trillian.TRUE : Trillian.FALSE;
		}

        // We only work out if the name is valid (or becomes valid
        // again) if the address becomes reachable.
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

    private inline string to_address_string() {
        // Unlikely to be the case, but if IPv6 format it nicely
        return (this.address.hostname.index_of(":") == -1)
            ? "%s:%u".printf(this.address.hostname, this.address.port)
            : "[%s]:%u".printf(this.address.hostname, this.address.port);
    }

}
