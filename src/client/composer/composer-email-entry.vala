/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A GTK entry for entering email addresses.
 */
public class Composer.EmailEntry : Gtk.Entry {

    /** The entry's list of possibly valid email addresses. */
    public Geary.RFC822.MailboxAddresses addresses {
        get { return this._addresses; }
        set {
            this._addresses = value;
            validate_addresses();
            this.is_modified = false;
            this.text = value.to_full_display();
        }
    }
    private Geary.RFC822.MailboxAddresses _addresses = new Geary.RFC822.MailboxAddresses();

    /** Determines if the entry contains only valid email addresses. */
    public bool is_valid { get; private set; default = false; }

    /** Determines if the entry contains any email addresses. */
    public bool is_empty {
        get {
            return this._addresses.is_empty;
        }
    }

    /**
     * Determines if the entry has been modified.
     *
     * The entry is considered to be modified only if the text has
     * been changed after it as been constructed or if modified after
     * setting {@link addresses}.
     */
    public bool is_modified { get; private set; default = false; }

    private weak Composer.Widget composer;


    public EmailEntry(Composer.Widget composer) {
        changed.connect(on_changed);
        key_press_event.connect(on_key_press);
        this.composer = composer;
        show();
    }

    /** Marks the entry as being modified. */
    public void set_modified() {
        this.is_modified = true;
    }

    private void validate_addresses() {
        bool is_valid = !this._addresses.is_empty;
        foreach (Geary.RFC822.MailboxAddress address in this.addresses) {
            if (!address.is_valid()) {
                is_valid = false;
                return;
            }
        }
        this.is_valid = is_valid;
    }

    private void on_changed() {
        this.is_modified = true;

        ContactEntryCompletion? completion =
            get_completion() as ContactEntryCompletion;
        if (completion != null) {
            completion.update_model();
        }

        if (Geary.String.is_empty_or_whitespace(text)) {
            this._addresses = new Geary.RFC822.MailboxAddresses();
            this.is_valid = false;
        } else {
            try {
                this._addresses =
                    new Geary.RFC822.MailboxAddresses.from_rfc822_string(text);
                this.is_valid = true;
            } catch (Geary.RFC822.Error err) {
                this._addresses = new Geary.RFC822.MailboxAddresses();
                this.is_valid = false;
            }
        }
    }

    private bool on_key_press(Gtk.Widget widget, Gdk.EventKey event) {
        bool propagate = Gdk.EVENT_PROPAGATE;
        if (event.keyval == Gdk.Key.Tab) {
            // If there is a completion entry selected, then use that
            ContactEntryCompletion? completion = (
                get_completion() as ContactEntryCompletion
            );
            if (completion != null) {
                completion.trigger_selection();
                composer.child_focus(Gtk.DirectionType.TAB_FORWARD);
                propagate = Gdk.EVENT_STOP;
            }
        }

        if (propagate == Gdk.EVENT_PROPAGATE &&
            event.keyval != Gdk.Key.Escape) {
            // Keyboard shortcuts for undo/redo won't work when the
            // completion UI is visible unless we explicitly check for
            // them there.
            //
            // However, don't forward it on if the button pressed is
            // Escape, so that the completion is hidden if present
            // before the composer is closed.
            Gtk.Window? window = get_toplevel() as Gtk.Window;
            if (window != null) {
                propagate = window.activate_key(event);
            }
        }
        return propagate;
    }
}
