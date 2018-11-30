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
    protected enum Trigger {
        /** The entry's contents changed */
        CHANGED,
        /** The user performed an action indicating they are done. */
        COMPLETE;
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

    private Geary.TimeoutManager ui_update_timer;


    public Validator(Gtk.Entry target) {
        this.target = target;

        this.ui_update_timer = new Geary.TimeoutManager.seconds(
            2, on_update_ui
        );

        this.indeterminate_state = {
            target.get_icon_name(ICON_POS),
            target.get_icon_tooltip_text(ICON_POS)
        };
        this.valid_state = {
            target.get_icon_name(ICON_POS),
            target.get_icon_tooltip_text(ICON_POS)
        };
        this.in_progress_state = { "process-working-symbolic", null};
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
    protected virtual Validity validate(string value, Trigger cause) {
        return Validity.VALID;
    }

    /**
     * Updates the current validation state and the entry's UI.
     *
     * This should only be called by subclasses that implement a
     * CPU-intensive or long-running validation routine and it has
     * completed validating a value. See {@link validate} for details.
     */
    protected void update_state(Validity new_state) {
        if (this.state != new_state) {
            Validity old_state = this.state;

            this.state = new_state;
            if (new_state == Validity.VALID) {
                // Update the UI straight away when going valid to
                // provide instant feedback
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
    }

    private void validate_entry(Trigger cause) {
        string value = this.target.get_text();
        Validity new_state = this.state;
        if (Geary.String.is_empty_or_whitespace(value)) {
            new_state = this.is_required
                ? Validity.EMPTY : Validity.INDETERMINATE;
        } else {
            new_state = validate(value, cause);
        }

        update_state(new_state);

        if (cause == Trigger.COMPLETE) {
            // Update the UI instantly since we know the user is done
            // editing it an will want instant feedback.
            update_ui(this.state);
        }
    }

    private void update_ui(Validity state) {
        this.ui_update_timer.reset();

        Gtk.StyleContext style = this.target.get_style_context();
        style.remove_class(Gtk.STYLE_CLASS_ERROR);
        style.remove_class(Gtk.STYLE_CLASS_WARNING);

        UiState ui = { null, null };
        switch (state) {
        case Validity.INDETERMINATE:
            ui = this.indeterminate_state;
            break;

        case Validity.VALID:
            ui = this.valid_state;
            break;

        case Validity.IN_PROGRESS:
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
        validate_entry(Trigger.COMPLETE);
    }

    private void on_update_ui() {
        update_ui(this.state);
    }

    private void on_changed() {
        validate_entry(Trigger.CHANGED);
        // Restart the UI timer if running to give the user some
        // breathing room while they are still editing.
        this.ui_update_timer.start();
    }

    private bool on_focus_out() {
        // Only update if the widget has lost focus due to not being
        // the focused widget any more, rather than the whole window
        // having lost focus.
        if (!this.target.is_focus) {
            validate_entry(Trigger.COMPLETE);
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


    protected override Validator.Validity validate(string value,
                                                   Validator.Trigger cause) {
        return Geary.RFC822.MailboxAddress.is_valid_address(value)
            ? Validator.Validity.VALID : Validator.Validity.INVALID;
    }

}
