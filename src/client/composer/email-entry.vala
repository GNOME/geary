/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Displays a dialog for collecting the user's login data.
public class EmailEntry : Gtk.Entry {
    public bool valid_or_empty { get; set; default = true; }
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
            text = (addresses == null) ? "" : addresses.to_rfc822_string();
            updating = false;
        });
    }

    private void on_changed() {
        if (updating)
            return;
        modified = true;

        ((ContactEntryCompletion) get_completion()).reset_selection();
        if (Geary.String.is_empty(text.strip())) {
            updating = true;
            addresses = null;
            updating = false;
            valid_or_empty = true;
            empty = true;
            return;
        }

        updating = true;
        addresses = new Geary.RFC822.MailboxAddresses.from_rfc822_string(text);
        updating = false;
    }
    
    private void validate_addresses() {
        if (addresses.size == 0) {
            valid_or_empty = true;
            empty = true;
            return;
        }
        empty = false;
        
        foreach (Geary.RFC822.MailboxAddress address in addresses) {
            if (!address.is_valid()) {
                valid_or_empty = false;
                return;
            }
        }
        valid_or_empty = true;
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

