/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class ContactEntryCompletion : Gtk.EntryCompletion, Geary.BaseInterface {


    // Minimum visibility for the contact to appear in autocompletion.
    private const Geary.Contact.Importance VISIBILITY_THRESHOLD =
        Geary.Contact.Importance.RECEIVED_FROM;


    public enum Column {
        CONTACT,
        MAILBOX;

        public static Type[] get_types() {
            return {
                typeof(Application.Contact), // CONTACT
                typeof(Geary.RFC822.MailboxAddress) // MAILBOX
            };
        }
    }


    private Application.ContactStore contacts;

    // Text between the start of the entry or of the previous email
    // address and the current position of the cursor, if any.
    private string current_key = "";

    // List of (possibly incomplete) email addresses in the entry.
    private string[] email_addresses = {};

    // Index of the email address the cursor is currently at
    private int cursor_at_address = -1;

    private GLib.Cancellable? search_cancellable = null;
    private Gtk.TreeIter? last_iter = null;


    public ContactEntryCompletion(Application.ContactStore contacts) {
        base_ref();
        this.contacts = contacts;
        this.model = new Gtk.ListStore.newv(Column.get_types());

        // Always match all rows, since the model will only contain
        // matching addresses from the search query
        set_match_func(() => true);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        pack_start(text_renderer, true);
        set_cell_data_func(text_renderer, cell_layout_data_func);

        set_inline_selection(true);
        match_selected.connect(on_match_selected);
        cursor_on_match.connect(on_cursor_on_match);
    }

    ~ContactEntryCompletion() {
        base_unref();
    }

    public void update_model() {
        this.last_iter = null;

        update_addresses();

        if (this.search_cancellable != null) {
            this.search_cancellable.cancel();
            this.search_cancellable = null;
        }

        string completion_key = this.current_key;
        if (!Geary.String.is_empty_or_whitespace(completion_key)) {
            this.search_cancellable = new GLib.Cancellable();
            this.search_contacts.begin(completion_key, this.search_cancellable);
        } else {
            ((Gtk.ListStore) this.model).clear();
        }
    }

    public void trigger_selection() {
        if (last_iter != null) {
            on_match_selected(model, last_iter);
            last_iter = null;
        }
    }

    private void update_addresses() {
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry != null) {
            this.current_key = "";
            this.cursor_at_address = -1;
            this.email_addresses = {};

            string text = entry.get_text();
            int cursor_pos = entry.get_position();

            int start_idx = 0;
            int next_idx = 0;
            unichar c = 0;
            int current_char = 0;
            bool in_quote = false;
            while (text.get_next_char(ref next_idx, out c)) {
                if (current_char == cursor_pos) {
                    this.current_key = text.slice(start_idx, next_idx).strip();
                    this.cursor_at_address = this.email_addresses.length;
                }

                switch (c) {
                case ',':
                    if (!in_quote) {
                        // Don't include the comma in the address
                        string address = text.slice(start_idx, next_idx -1);
                        this.email_addresses += address.strip();
                        // Don't include it in the next one, either
                        start_idx = next_idx;
                    }
                    break;

                case '"':
                    in_quote = !in_quote;
                    break;
                }

                current_char++;
            }

            // Add any remaining text after the last comma
            string address = text.substring(start_idx);
            this.email_addresses += address.strip();
        }
    }

    public async void search_contacts(string query,
                                      GLib.Cancellable? cancellable) {
        try {
            Gee.Collection<Application.Contact> results =
                yield this.contacts.search(
                    query,
                    VISIBILITY_THRESHOLD,
                    20,
                    cancellable
                );

            Gtk.ListStore model = (Gtk.ListStore) this.model;
            model.clear();
            foreach (Application.Contact contact in results) {
                foreach (Geary.RFC822.MailboxAddress addr
                         in contact.email_addresses) {
                    Gtk.TreeIter iter;
                    model.append(out iter);
                    model.set(iter, Column.CONTACT, contact);
                    model.set(iter, Column.MAILBOX, addr);
                }
            }

            // Ensure completion is visible if loading finishes after
            // the base class's handler has triggered a completion
            complete();
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (GLib.Error err) {
            debug("Error searching contacts for completion: %s", err.message);
        }
    }

    private string match_prefix_contact(Geary.RFC822.MailboxAddress mailbox) {
        string email = match_prefix_string(mailbox.address);
        if (mailbox.name != null && !mailbox.is_spoofed()) {
            string real_name = match_prefix_string(mailbox.name);
            // email and real_name were already escaped, then <b></b> tags
            // were added to highlight matches. We don't want to escape
            // them again.
            email = (
                real_name +
                Markup.escape_text(" <") + email + Markup.escape_text(">")
            );
        }
        return email;
    }

    private string? match_prefix_string(string haystack) {
        string value = haystack;
        if (!Geary.String.is_empty(this.current_key)) {
            bool matched = false;
            try {
                string escaped_needle = Regex.escape_string(
                    this.current_key.normalize()
                );
                Regex regex = new Regex(
                    "\\b" + escaped_needle,
                    RegexCompileFlags.CASELESS
                );
                string haystack_normalized = haystack.normalize();
                if (regex.match(haystack_normalized)) {
                    value = regex.replace_eval(
                        haystack_normalized, -1, 0, 0, eval_callback
                    );
                    matched = true;
                }
            } catch (RegexError err) {
                debug("Error matching regex: %s", err.message);
            }

            if (matched) {
                value = Markup.escape_text(value)
                    .replace("&#x91;", "<b>")
                    .replace("&#x92;", "</b>");
            }
        }

        return value;
    }

    private bool eval_callback(GLib.MatchInfo match_info,
                               GLib.StringBuilder result) {
        string? match = match_info.fetch(0);
        if (match != null) {
            result.append("\xc2\x91%s\xc2\x92".printf(match));
            // This is UTF-8 encoding of U+0091 and U+0092
        }
        return false;
    }

    private void cell_layout_data_func(Gtk.CellLayout cell_layout,
                                       Gtk.CellRenderer cell,
                                       Gtk.TreeModel tree_model,
                                       Gtk.TreeIter iter) {
        GLib.Value value;
        tree_model.get_value(iter, Column.MAILBOX, out value);
        Geary.RFC822.MailboxAddress mailbox =
            (Geary.RFC822.MailboxAddress) value.get_object();

        string render = this.match_prefix_contact(mailbox);

        Gtk.CellRendererText renderer = (Gtk.CellRendererText) cell;
        renderer.markup = render;
    }

    private bool on_match_selected(Gtk.TreeModel model, Gtk.TreeIter iter) {
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry != null) {
            // Update the address
            GLib.Value value;
            model.get_value(iter, Column.MAILBOX, out value);
            Geary.RFC822.MailboxAddress mailbox =
                (Geary.RFC822.MailboxAddress) value.get_object();
            this.email_addresses[this.cursor_at_address] =
                mailbox.to_full_display();

            // Update the entry text
            bool current_is_last = (
                this.cursor_at_address == this.email_addresses.length - 1
            );
            int new_cursor_pos = -1;
            GLib.StringBuilder text = new GLib.StringBuilder();
            int i = 0;
            while (i < this.email_addresses.length) {
                text.append(this.email_addresses[i]);
                if (i == this.cursor_at_address) {
                    new_cursor_pos = text.str.char_count();
                }

                i++;
                if (i != this.email_addresses.length || current_is_last) {
                    text.append(", ");
                }
            }
            entry.text = text.str;
            entry.set_position(current_is_last ? -1 : new_cursor_pos);
        }
        return true;
    }

    private bool on_cursor_on_match(Gtk.TreeModel model, Gtk.TreeIter iter) {
        this.last_iter = iter;
        return true;
    }

}
