/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A custom entry for e-mail addresses
public class EmailEntry : Gtk.Entry {
    // Whether this entry contains a valid email address
    public bool valid { get; set; default = false; }

    public bool empty { get; set; default = true; }

    public bool modified = false;

    // null or valid addresses
    public Geary.RFC822.MailboxAddresses? addresses { get; set; default = null; }

    private weak ComposerWidget composer;

    private bool updating = false;

    public EmailEntry(ComposerWidget composer) {
        changed.connect(on_changed);
        key_press_event.connect(on_key_press);
        this.composer = composer;

        notify["addresses"].connect(() => {
            validate_addresses();
            if (updating)
                return;

            updating = true;
            modified = true;
            text = (addresses == null) ? "" : addresses.to_full_display();
            updating = false;
        });

        show();
    }

    private void on_changed() {
        if (updating)
            return;
        modified = true;

        ContactEntryCompletion? completion = get_completion() as ContactEntryCompletion;
        if (completion != null) {
            completion.update_model();
        }

        if (Geary.String.is_empty(text.strip())) {
            updating = true;
            addresses = null;
            updating = false;
            valid = false;
            empty = true;
            return;
        }

        updating = true;
        addresses = new Geary.RFC822.MailboxAddresses.from_rfc822_string(text);
        updating = false;
    }

    private void validate_addresses() {
        if (addresses == null || addresses.size == 0) {
            valid = false;
            empty = true;
            return;
        }
        empty = false;

        foreach (Geary.RFC822.MailboxAddress address in addresses) {
            if (!address.is_valid()) {
                valid = false;
                return;
            }
        }
        valid = true;
    }

    private bool on_key_press(Gtk.Widget widget, Gdk.EventKey event) {
        if (event.keyval == Gdk.Key.Tab) {
            ((ContactEntryCompletion) get_completion()).trigger_selection();
            composer.child_focus(Gtk.DirectionType.TAB_FORWARD);
            return true;
        }

        return false;
    }
}

