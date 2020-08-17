/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Validates the contents of a Gtk Entry as they are entered.
 *
 * This class may be used to validate required, but otherwise free
 * form entries. Subclasses may perform more complex and task-specific
 * validation.
 */
public class Components.Validator : GLib.Object {


    private const Gtk.EntryIconPosition ICON_POS =
        Gtk.EntryIconPosition.SECONDARY;


    /**
     * The state of the entry monitored by this validator.
     *
     * Only {@link VALID} can be considered strictly valid, all other
     * states should be treated as being invalid.
     */
    public enum Validity {
        /** The contents of the entry have not been validated. */
        INDETERMINATE,

        /** The contents of the entry is valid. */
        VALID,

        /**
         * The contents of the entry is being checked.
         *
         * See {@link validate} for the use of this value.
         */
        IN_PROGRESS,

        /** The contents of the entry is required but not present. */
        EMPTY,

        /** The contents of the entry is not valid. */
        INVALID;
    }

    /** The cause of a validity check being required. */
    public enum Trigger {
        /** A manual validation was requested via {@link validate}. */
        MANUAL,
        /** The entry's contents changed. */
        CHANGED,
        /** The entry lost the keyboard focus. */
        LOST_FOCUS,
        /** The user activated the entry. */
        ACTIVATED;
    }

    /** Defines the UI state for a specific validity. */
    protected struct UiState {
        public string? icon_name;
        public string? icon_tooltip_text;
    }

    /** The entry being monitored */
    public Gtk.Entry target { get; private set; }

    /** Determines if the current state indicates the entry is valid. */
    public bool is_valid {
        get { return (this.state == Validity.VALID); }
    }

    /**
     * Determines how empty entries are treated.
     *
     * If true, an empty entry is considered {@link Validity.EMPTY}
     * (i.e. invalid) else it is considered to be {@link
     * Validity.INDETERMINATE}.
     */
    public bool is_required { get; set; default = true; }

    /** The current validation state of the entry. */
    public Validity state {
        get; private set; default = Validity.INDETERMINATE;
    }

    /** The UI state to use when indeterminate. */
    public UiState indeterminate_state;

    /** The UI state to use when valid. */
    public UiState valid_state;

    /** The UI state to use when in progress. */
    public UiState in_progress_state;

    /** The UI state to use when empty. */
    public UiState empty_state;

    /** The UI state to use when invalid. */
    public UiState invalid_state;

    // Determines if the value has changed since last validation
    private bool target_changed = false;

    private Geary.TimeoutManager ui_update_timer;

    private Geary.TimeoutManager pulse_timer;
    bool did_pulse = false;


    /** Fired when the validation state changes. */
    public signal void state_changed(Trigger reason, Validity prev_state);

    /** Fired when validation completes after the target has changed. */
    public signal void changed();

    /** Fired when validation completes after the target was activated. */
    public signal void activated();

    /** Fired when validation completes after the target lost focus. */
    public signal void focus_lost();


    public Validator(Gtk.Entry target) {
        this.target = target;

        this.ui_update_timer = new Geary.TimeoutManager.seconds(
            2, on_update_ui
        );

        this.pulse_timer = new Geary.TimeoutManager.milliseconds(
            200, on_pulse
        );
        this.pulse_timer.repetition = FOREVER;

        this.indeterminate_state = {
            target.get_icon_name(ICON_POS),
            target.get_icon_tooltip_text(ICON_POS)
        };
        this.valid_state = {
            target.get_icon_name(ICON_POS),
            target.get_icon_tooltip_text(ICON_POS)
        };
        this.in_progress_state = {
            target.get_icon_name(ICON_POS),
            null
        };
        this.empty_state = { "dialog-warning-symbolic", null };
        this.invalid_state = { "dialog-error-symbolic", null };

        this.target.add_events(Gdk.EventMask.FOCUS_CHANGE_MASK);
        this.target.activate.connect(on_activate);
        this.target.changed.connect(on_changed);
        this.target.focus_out_event.connect(on_focus_out);
    }

    ~Validator() {
        this.target.focus_out_event.disconnect(on_focus_out);
        this.target.changed.disconnect(on_changed);
        this.target.activate.disconnect(on_activate);
        this.ui_update_timer.reset();
        this.pulse_timer.reset();
    }

    /**
     * Triggers a validation of the entry.
     *
     * In the case of an asynchronous validation implementations,
     * result of the validation will be known sometime after this call
     * has completed.
     */
    public void validate() {
        validate_entry(MANUAL);
    }

    /**
     * Called to validate the target entry's value.
     *
     * This method will be called repeatedly as the user edits the
     * value of the target entry to set the new validation {@link
     * state} given the updated value. It will *not* be called if the
     * entry is changed to be empty, instead the validity state will
     * be set based on {@link is_required}.
     *
     * Subclasses may override this method to implement custom
     * validation routines. Since this call is made repeatedly as the
     * user is typing, it should not perform a CPU-intensive or
     * long-running routine. Subclasses that do perform such
     * validation should launch the routine in the background (either
     * asynchronously or in a thread) and return {@link
     * Validity.IN_PROGRESS} as soon as possible. Then, when it is
     * complete, call {@link update_state} to update the validity state
     * with the actual result.
     *
     * The given reason specifies which user action was taken to cause
     * the entry's value to be validated.
     *
     * By default, this always returns {@link Validity.VALID}, making
     * it useful for required, but otherwise free-form fields only.
     */
    protected virtual Validity do_validate(string value, Trigger reason) {
        return Validity.VALID;
    }

    /**
     * Updates the current validation state and the entry's UI.
     *
     * This should only be called by subclasses that implement a
     * CPU-intensive or long-running validation routine and it has
     * completed validating a value. See {@link validate} for details.
     */
    protected void update_state(Validity new_state, Trigger reason) {
        if (this.state != new_state) {
            Validity old_state = this.state;

            // Fire the signal after updating the state but before
            // updating the UI so listeners can update UI settings
            // first if needed.
            this.state = new_state;
            notify_property("is-valid");
            state_changed(reason, old_state);

            if (new_state == Validity.VALID || reason != Trigger.CHANGED) {
                // Update the UI straight away when going valid or
                // when editing is complete to provide instant
                // feedback
                update_ui(new_state);
            } else {
                if (old_state == Validity.EMPTY) {
                    // Technically this is a lie, but when going from
                    // empty to non-empty we also want to provide
                    // instant feedback, and going to indeterminate
                    // when the user is in the middle of editing is
                    // better than going to invalid.
                    update_ui(Validity.INDETERMINATE);
                }
                // Start the a timer running to update the UI to give
                // the timer running since they might still be editing
                // it.
                this.ui_update_timer.start();
            }
        }

        if (new_state != Validity.IN_PROGRESS) {
            this.target_changed = false;

            switch (reason) {
            case Trigger.CHANGED:
                changed();
                break;

            case Trigger.ACTIVATED:
                activated();
                break;

            case Trigger.LOST_FOCUS:
                focus_lost();
                break;

            case Trigger.MANUAL:
                // no-op
                break;
            }
        } else if (!this.pulse_timer.is_running) {
            this.pulse_timer.start();
        }
    }

    private void validate_entry(Trigger reason) {
        string value = this.target.get_text();
        Validity new_state = this.state;
        if (Geary.String.is_empty_or_whitespace(value)) {
            new_state = this.is_required ? Validity.EMPTY : Validity.VALID;
        } else {
            new_state = do_validate(value, reason);
        }
        update_state(new_state, reason);
    }

    private void update_ui(Validity state) {
        this.ui_update_timer.reset();

        Gtk.StyleContext style = this.target.get_style_context();
        style.remove_class(Gtk.STYLE_CLASS_ERROR);
        style.remove_class(Gtk.STYLE_CLASS_WARNING);

        UiState ui = { null, null };
        bool in_progress = false;
        switch (state) {
        case Validity.INDETERMINATE:
            ui = this.indeterminate_state;
            break;

        case Validity.VALID:
            ui = this.valid_state;
            break;

        case Validity.IN_PROGRESS:
            in_progress = true;
            ui = this.in_progress_state;
            break;

        case Validity.EMPTY:
            style.add_class(Gtk.STYLE_CLASS_WARNING);
            ui = this.empty_state;
            break;

        case Validity.INVALID:
            style.add_class(Gtk.STYLE_CLASS_ERROR);
            ui = this.invalid_state;
            break;
        }

        if (in_progress) {
            if (!this.pulse_timer.is_running) {
                this.pulse_timer.start();
            }
        } else {
            this.pulse_timer.reset();
            // If a pulse hasn't been performed (and hence the
            // progress bar is not visible), setting the fraction here
            // to reset it will actually cause the progress bar to
            // become visible. So only reset if needed.
            if (this.did_pulse) {
                this.target.progress_fraction = 0.0;
                this.did_pulse = false;
            }
        }

        this.target.set_icon_from_icon_name(ICON_POS, ui.icon_name);
        this.target.set_icon_tooltip_text(
            ICON_POS,
            // Setting the tooltip to null or the empty string can
            // cause GTK+ to setfult. See GTK+ issue #1160.
            Geary.String.is_empty(ui.icon_tooltip_text)
                ? " " : ui.icon_tooltip_text
        );
    }

    private void on_activate() {
        if (this.target_changed) {
             validate_entry(Trigger.ACTIVATED);
        } else {
            activated();
        }
    }

    private void on_update_ui() {
        update_ui(this.state);
    }

    private void on_pulse() {
        this.target.progress_pulse();
        this.did_pulse = true;
    }

    private void on_changed() {
        this.target_changed = true;
        validate_entry(Trigger.CHANGED);
        // Restart the UI timer if running to give the user some
        // breathing room while they are still editing.
        this.ui_update_timer.start();
    }

    private bool on_focus_out() {
        if (this.target_changed) {
            // Only update if the widget has lost focus due to not being
            // the focused widget any more, rather than the whole window
            // having lost focus.
            if (!this.target.is_focus) {
                validate_entry(Trigger.LOST_FOCUS);
            }
        } else {
            focus_lost();
        }
        return Gdk.EVENT_PROPAGATE;
    }

}


/**
 * A validator for GTK Entry widgets that contain an email address.
 */
public class Components.EmailValidator : Validator {

    public EmailValidator(Gtk.Entry target) {
        base(target);

        // Translators: Tooltip used when an entry requires a valid
        // email address to be entered, but one is not provided.
        this.empty_state.icon_tooltip_text = _("An email address is required");

        // Translators: Tooltip used when an entry requires a valid
        // email address to be entered, but the address is invalid.
        this.invalid_state.icon_tooltip_text = _("Not a valid email address");
    }


    protected override Validator.Validity do_validate(string value,
                                                      Validator.Trigger reason) {
        return Geary.RFC822.MailboxAddress.is_valid_address(value)
            ? Validator.Validity.VALID : Validator.Validity.INVALID;
    }

}


/**
 * A validator for GTK Entry widgets that contain a network address.
 *
 * This attempts parse the entry value as a host name or IP address
 * with an optional port, then resolve the host name if
 * needed. Parsing is performed by {@link GLib.NetworkAddress.parse}
 * to parse the user input, hence it may be specified in any form
 * supported by that method.
 */
public class Components.NetworkAddressValidator : Validator {


    /** The validated network address, if any. */
    public GLib.NetworkAddress? validated_address {
        get; private set; default = null;
    }

    /** The default port used when parsing the address. */
    public uint16 default_port { get; private set; }

    private GLib.Resolver resolver;
    private GLib.Cancellable? cancellable = null;


    public NetworkAddressValidator(Gtk.Entry target, uint16 default_port = 0) {
        base(target);
        this.default_port = default_port;

        this.resolver = GLib.Resolver.get_default();

        // Translators: Tooltip used when an entry requires a valid,
        // resolvable server name to be entered, but one is not
        // provided.
        this.empty_state.icon_tooltip_text = _("A server name is required");

        // Translators: Tooltip used when an entry requires a valid
        // server name to be entered, but it was unable to be
        // looked-up in the DNS.
        this.invalid_state.icon_tooltip_text = _("Could not look up server name");
    }


    public override Validator.Validity do_validate(string value,
                                                   Validator.Trigger reason) {
        if (this.cancellable != null) {
            this.cancellable.cancel();
        }

        Validator.Validity ret = this.state;

        GLib.NetworkAddress? address = null;
        try {
            address = GLib.NetworkAddress.parse(
                value.strip(), this.default_port
            );
        } catch (GLib.Error err) {
            this.validated_address = null;
            ret = Validator.Validity.INVALID;
            debug("Error parsing host name \"%s\": %s", value, err.message);
        }

        if (address != null) {
            // Re-validate if previously invalid or the host has
            // changed
            if (this.validated_address == null ||
                this.validated_address.hostname != address.hostname) {
                this.cancellable = new GLib.Cancellable();
                this.resolver.lookup_by_name_async.begin(
                    address.hostname, this.cancellable,
                    (obj, res) => {
                        try {
                            this.resolver.lookup_by_name_async.end(res);
                            this.validated_address = address;
                            update_state(Validator.Validity.VALID, reason);
                        } catch (GLib.IOError.CANCELLED err) {
                            this.validated_address = null;
                        } catch (GLib.Error err) {
                            this.validated_address = null;
                            update_state(Validator.Validity.INVALID, reason);
                        }
                        this.cancellable = null;
                    }
                );
                ret = Validator.Validity.IN_PROGRESS;
            } else {
                // Update the validated address in case the port
                // number is being edited and has changed
                this.validated_address = address;
                ret = Validator.Validity.VALID;
            }
        }

        return ret;
    }

}
