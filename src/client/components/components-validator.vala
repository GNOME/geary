/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Validates the contents of a Gtk Editable as they are entered.
 *
 * This class may be used to validate required, but otherwise free
 * form entries. Subclasses may perform more complex and task-specific
 * validation.
 */
public class Components.Validator : GLib.Object {


    /**
     * The state of the editable monitored by this validator.
     *
     * Only {@link VALID} can be considered strictly valid, all other
     * states should be treated as being invalid.
     */
    public enum Validity {
        /** The contents of the editable have not been validated. */
        INDETERMINATE,

        /** The contents of the editable is valid. */
        VALID,

        /**
         * The contents of the editable is being checked.
         *
         * See {@link validate} for the use of this value.
         */
        IN_PROGRESS,

        /** The contents of the editable is required but not present. */
        EMPTY,

        /** The contents of the editable is not valid. */
        INVALID;
    }

    /** The cause of a validity check being required. */
    public enum Trigger {
        /** A manual validation was requested via {@link validate}. */
        MANUAL,
        /** The editable's contents changed. */
        CHANGED,
        /** The editable lost the keyboard focus. */
        LOST_FOCUS,
        /** The user activated the editable. */
        ACTIVATED;
    }

    /** Defines the UI state for a specific validity. */
    protected struct UiState {
        public string? icon_name;
        public string? icon_tooltip_text;
    }

    /** The editable being monitored */
    public Gtk.Editable target {
        get { return this._target; }
        construct set {
            this._target = value;
            if (value is Gtk.Entry) {
                this.target_helper = new EntryHelper((Gtk.Entry) value);
            } else if (value is Adw.EntryRow) {
                this.target_helper = new EntryRowHelper((Adw.EntryRow) value);
            } else {
                critical("Validator for type '%s' unsupported", value.get_type().name());
            }
        }
    }
    private Gtk.Editable _target;
    protected EditableHelper target_helper;

    private Gtk.EventControllerFocus target_focus_controller = new Gtk.EventControllerFocus();

    /** Determines if the current state indicates the editable is valid. */
    public bool is_valid {
        get { return (this.state == Validity.VALID); }
    }

    /**
     * Determines how empty entries are treated.
     *
     * If true, an empty editable is considered {@link Validity.EMPTY}
     * (i.e. invalid) else it is considered to be {@link
     * Validity.INDETERMINATE}.
     */
    public bool is_required { get; set; default = true; }

    /** The current validation state of the editable. */
    public Validity state {
        get; private set; default = Validity.INDETERMINATE;
    }

    // Determines if the value has changed since last validation
    private bool target_changed = false;

    private Geary.TimeoutManager ui_update_timer;


    /** Fired when the validation state changes. */
    public signal void state_changed(Trigger reason, Validity prev_state);

    /** Fired when validation completes after the target has changed. */
    public signal void changed();

    /** Fired when validation completes after the target was activated. */
    public signal void activated();

    /** Fired when validation completes after the target lost focus. */
    public signal void focus_lost();


    construct {
        this.ui_update_timer = new Geary.TimeoutManager.seconds(
            1, on_update_ui
        );

        this.target_helper.activated.connect(on_activate);
        this.target.changed.connect(on_changed);
        this.target_focus_controller.leave.connect(on_focus_out);
        this.target.add_controller(this.target_focus_controller);
    }


    public Validator(Gtk.Editable target) {
        GLib.Object(target: target);
    }

    ~Validator() {
        this.ui_update_timer.reset();
    }

    /**
     * Triggers a validation of the editable.
     *
     * In the case of an asynchronous validation implementations,
     * result of the validation will be known sometime after this call
     * has completed.
     */
    public void validate() {
        validate_entry(MANUAL);
    }

    /**
     * Called to validate the target editable's value.
     *
     * This method will be called repeatedly as the user edits the
     * value of the target editable to set the new validation {@link
     * state} given the updated value. It will *not* be called if the
     * editable is changed to be empty, instead the validity state will
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
     * the editable's value to be validated.
     *
     * By default, this always returns {@link Validity.VALID}, making
     * it useful for required, but otherwise free-form fields only.
     */
    protected virtual Validity do_validate(string value, Trigger reason) {
        return Validity.VALID;
    }

    /**
     * Updates the current validation state and the editable's UI.
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

        this.target_helper.update_ui(state);
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

    private void on_changed() {
        this.target_changed = true;
        validate_entry(Trigger.CHANGED);
        // Restart the UI timer if running to give the user some
        // breathing room while they are still editing.
        this.ui_update_timer.start();
    }

    private void on_focus_out(Gtk.EventControllerFocus controller) {
        if (this.target_changed) {
            // Only update if the widget has lost focus due to not being
            // the focused widget any more, rather than the whole window
            // having lost focus.
            if (!this.target.is_focus()) {
                validate_entry(Trigger.LOST_FOCUS);
            }
        } else {
            focus_lost();
        }
    }

}

/**
 * A helper class to set an icon, abstracting away the underlying API of the
 * Gtk.Editable implementation.
 */
protected abstract class Components.EditableHelper : Object {

    /** Tooltip text in case the validator returns an invalid state */
    public string? invalid_tooltip_text { get; set; default = null; }

    /** Tooltip text in case the validator returns an empty state */
    public string? empty_tooltip_text { get; set; default = null; }

    /** Emitted if the editable has been activated */
    public signal void activated();

    /** Sets an error icon with the given name and tooltip */
    public abstract void update_ui(Validator.Validity state);
}


private class Components.EntryHelper : EditableHelper {

    private unowned Gtk.Entry entry;

    public EntryHelper(Gtk.Entry entry) {
        this.entry = entry;
        this.entry.activate.connect((e) => this.activated());
    }

    public override void update_ui(Validator.Validity state) {
        this.entry.remove_css_class("error");
        this.entry.remove_css_class("warning");

        switch (state) {
        case Validator.Validity.INDETERMINATE:
        case Validator.Validity.VALID:
            // Reset
            this.entry.secondary_icon_name = "";
            this.entry.secondary_icon_tooltip_text = "";
            break;

        case Validator.Validity.IN_PROGRESS:
            this.entry.secondary_icon_paintable = new Adw.SpinnerPaintable(this.entry);
            this.entry.secondary_icon_tooltip_text = _("Validating");
            break;

        case Validator.Validity.EMPTY:
            this.entry.add_css_class("warning");
            this.entry.secondary_icon_name = "dialog-warning-symbolic";
            this.entry.secondary_icon_tooltip_text = this.empty_tooltip_text ?? "";
            break;

        case Validator.Validity.INVALID:
            this.entry.add_css_class("error");
            this.entry.secondary_icon_name = "dialog-error-symbolic";
            this.entry.secondary_icon_tooltip_text = this.invalid_tooltip_text ?? "";
            break;
        }
    }
}

private class Components.EntryRowHelper : EditableHelper {

    private unowned Adw.EntryRow row;

    private unowned Adw.Spinner? spinner = null;
    private unowned Gtk.Image? error_image = null;

    public EntryRowHelper(Adw.EntryRow row) {
        this.row = row;
        this.row.entry_activated.connect((e) => this.activated());
    }

    public override void update_ui(Validator.Validity state) {
        reset();

        this.row.remove_css_class("error");
        this.row.remove_css_class("warning");

        switch (state) {
        case Validator.Validity.INDETERMINATE:
        case Validator.Validity.VALID:
            break;

        case Validator.Validity.IN_PROGRESS:
            var spinner = new Adw.Spinner();
            spinner.tooltip_text = _("Validating");
            this.row.add_suffix(spinner);
            this.spinner = spinner;
            break;

        case Validator.Validity.EMPTY:
            this.row.add_css_class("warning");
            var img = new Gtk.Image.from_icon_name("dialog-warning-symbolic");
            img.tooltip_text = this.empty_tooltip_text ?? "";
            this.row.add_suffix(img);
            this.error_image = img;
            break;

        case Validator.Validity.INVALID:
            this.row.add_css_class("error");
            var img = new Gtk.Image.from_icon_name("dialog-error-symbolic");
            img.tooltip_text = this.invalid_tooltip_text ?? "";
            this.row.add_suffix(img);
            this.error_image = img;
            break;
        }
    }

    private void reset() {
        if (this.spinner != null) {
            this.row.remove(this.spinner);
            this.spinner = null;
        }
        if (this.error_image != null) {
            this.row.remove(this.error_image);
            this.error_image = null;
        }
    }
}


/**
 * A validator for GTK Editable widgets that contain an email address.
 */
public class Components.EmailValidator : Validator {

    construct {
        // Translators: Tooltip used when an editable requires a valid
        // email address to be entered, but one is not provided.
        this.target_helper.empty_tooltip_text = _("An email address is required");

        // Translators: Tooltip used when an editablerequires a valid
        // email address to be entered, but the address is invalid.
        this.target_helper.invalid_tooltip_text = _("Not a valid email address");
    }

    public EmailValidator(Gtk.Editable target) {
        GLib.Object(target: target);
    }

    protected override Validator.Validity do_validate(string value,
                                                      Validator.Trigger reason) {
        return Geary.RFC822.MailboxAddress.is_valid_address(value)
            ? Validator.Validity.VALID : Validator.Validity.INVALID;
    }

}


/**
 * A validator for Gtk.Editable widgets that contain a network address.
 *
 * This attempts parse the editable value as a host name or IP address
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
    public uint16 default_port { get; construct set; }

    private GLib.Resolver resolver;
    private GLib.Cancellable? cancellable = null;

    construct {
        this.resolver = GLib.Resolver.get_default();

        // Translators: Tooltip used when an editable requires a valid,
        // resolvable server name to be entered, but one is not
        // provided.
        this.target_helper.empty_tooltip_text = _("A server name is required");

        // Translators: Tooltip used when an editable requires a valid
        // server name to be entered, but it was unable to be
        // looked-up in the DNS.
        this.target_helper.invalid_tooltip_text = _("Could not look up server name");
    }

    public NetworkAddressValidator(Gtk.Editable target, uint16 default_port = 0) {
        GLib.Object(
            target: target,
            default_port: default_port
        );
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
