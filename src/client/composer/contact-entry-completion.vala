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
    private Gee.ArrayList<string> address_parts = new Gee.ArrayList<string>();

    // Index of the email address the cursor is currently at
    private int cursor_at_address = 0;

    private GLib.Cancellable? search_cancellable = null;
    private Gtk.TreeIter? last_iter = null;


    public ContactEntryCompletion(Application.ContactStore contacts) {
        base_ref();
        this.contacts = contacts;
        this.model = new_model();

        // Always match all rows, since the model will only contain
        // matching addresses from the search query
        set_match_func(() => true);

        Gtk.CellRendererPixbuf icon_renderer = new Gtk.CellRendererPixbuf();
        icon_renderer.xpad = 2;
        icon_renderer.ypad = 2;
        pack_start(icon_renderer, false);
        set_cell_data_func(icon_renderer, cell_icon_data);

        Gtk.CellRendererText text_renderer = new Gtk.CellRendererText();
        icon_renderer.ypad = 2;
        pack_start(text_renderer, true);
        set_cell_data_func(text_renderer, cell_text_data);

        // cursor-on-match isn't fired unless this is true
        this.inline_selection = true;

        this.match_selected.connect(on_match_selected);
        this.cursor_on_match.connect(on_cursor_on_match);
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

        Gtk.ListStore model = (Gtk.ListStore) this.model;
        string completion_key = this.current_key;
        if (!Geary.String.is_empty_or_whitespace(completion_key)) {
            this.search_cancellable = new GLib.Cancellable();
            this.search_contacts.begin(completion_key, this.search_cancellable);
        } else {
            model.clear();
        }
    }

    public void trigger_selection() {
        if (this.last_iter != null) {
            insert_address_at_cursor(this.last_iter);
            this.last_iter = null;
        }
    }

    private void update_addresses() {
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry != null) {
            this.current_key = "";
            this.cursor_at_address = 0;
            this.address_parts.clear();

            // NB: Do not strip any white space from the addresses,
            // otherwise we won't be able to accurately insert
            // addresses in the middle of the list in
            // ::insert_address_at_cursor.

            string text = entry.get_text();
            int cursor_pos = entry.get_position();

            int current_char = 0;
            unichar c = 0;
            int start_idx = 0;
            int next_idx = 0;
            bool in_quote = false;
            while (text.get_next_char(ref next_idx, out c)) {
                if (current_char == cursor_pos &&
                    current_char != 0) {
                    if (c != ',' ) {
                        // Strip whitespace here though so it does not
                        // interfere with search and highlighting.
                        this.current_key = text.slice(
                            start_idx, next_idx
                        ).strip();
                    }
                    // We're in the middle of the address, so it
                    // hasn't yet been added to the list and hence we
                    // don't need to subtract 1 from its size here
                    this.cursor_at_address = this.address_parts.size;
                }

                switch (c) {
                case ',':
                    if (!in_quote) {
                        // Don't include the comma in the address
                        string address = text.slice(start_idx, next_idx - 1);
                        this.address_parts.add(address);
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
            this.address_parts.add(address);
        }
    }

    private void insert_address_at_cursor(Gtk.TreeIter iter) {
        Gtk.Entry? entry = get_entry() as Gtk.Entry;
        if (entry != null) {

            // Take care to do a delete then an insert here so that
            // Component.EntryUndo can combine the two into a single
            // undoable command.

            int start_char = 0;
            if (this.cursor_at_address > 0) {
                start_char = this.address_parts.slice(
                    0, this.cursor_at_address
                ).fold<int>(
                    // Address parts don't contain commas, so need to add
                    // an char width for it. Don't need to worry about
                    // spaces because they are preserved by
                    // ::update_addresses.
                    (a, chars) => a.char_count() + chars + 1, 0
                );
            }
            int end_char = entry.get_position();

            // Format and use the selected address
            GLib.Value value;
            this.model.get_value(iter, Column.MAILBOX, out value);
            Geary.RFC822.MailboxAddress mailbox =
                (Geary.RFC822.MailboxAddress) value.get_object();
            string formatted = mailbox.to_full_display();
            if (this.cursor_at_address != 0) {
                // Isn't the first address, so add some whitespace to
                // pad it out
                formatted = " " + formatted;
            }
            if (entry.get_position() < entry.buffer.get_length() &&
                this.address_parts[this.cursor_at_address].strip() !=
                this.current_key.strip()) {
                // Isn't at the end of the entry, and the address
                // under the cursor does not simply consist of the
                // lookup key (i.e. is effectively already empty
                // otherwise), so add a comma to separate this address
                // from the next one
                formatted = formatted + ", ";
            }
            this.address_parts.insert(this.cursor_at_address, formatted);

            // Update the entry text
            if (start_char < end_char) {
                entry.delete_text(start_char, end_char);
            }
            entry.insert_text(formatted, -1, ref start_char);

            // Update the entry cursor position. The previous call
            // updates the start so just use that, but add extra space
            // for the comma and any white space at the start of the
            // next address.
            if (start_char < entry.buffer.get_length()) {
                start_char += 2;
            }
            entry.set_position(start_char);
        }
    }

    private async void search_contacts(string query,
                                       GLib.Cancellable? cancellable) {
        Gee.Collection<Application.Contact>? results = null;
        try {
            results = yield this.contacts.search(
                query,
                VISIBILITY_THRESHOLD,
                20,
                cancellable
            );
        } catch (GLib.IOError.CANCELLED err) {
            // All good
        } catch (GLib.Error err) {
            debug("Error searching contacts for completion: %s", err.message);
        }

        if (!cancellable.is_cancelled()) {
            Gtk.ListStore model = new_model();
            foreach (Application.Contact contact in results) {
                foreach (Geary.RFC822.MailboxAddress addr
                         in contact.email_addresses) {
                    Gtk.TreeIter iter;
                    model.append(out iter);
                    model.set(iter, Column.CONTACT, contact);
                    model.set(iter, Column.MAILBOX, addr);
                }
            }
            this.model = model;
            complete();
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

            value = Markup.escape_text(value)
                .replace("&#x91;", "<b>")
                .replace("&#x92;", "</b>");
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

    private void cell_icon_data(Gtk.CellLayout cell_layout,
                                Gtk.CellRenderer cell,
                                Gtk.TreeModel tree_model,
                                Gtk.TreeIter iter) {
        GLib.Value value;
        tree_model.get_value(iter, Column.CONTACT, out value);
        Application.Contact? contact = value.get_object() as Application.Contact;

        string icon = "";
        if (contact != null) {
            if (contact.is_favourite) {
                icon = "starred-symbolic";
            } else if (contact.is_desktop_contact) {
                icon = "avatar-default-symbolic";
            }
        }

        Gtk.CellRendererPixbuf renderer = (Gtk.CellRendererPixbuf) cell;
        renderer.icon_name = icon;
    }

    private void cell_text_data(Gtk.CellLayout cell_layout,
                                Gtk.CellRenderer cell,
                                Gtk.TreeModel tree_model,
                                Gtk.TreeIter iter) {
        GLib.Value value;
        tree_model.get_value(iter, Column.MAILBOX, out value);
        Geary.RFC822.MailboxAddress? mailbox =
            value.get_object() as Geary.RFC822.MailboxAddress;

        string markup = "";
        if (mailbox != null) {
            markup = this.match_prefix_contact(mailbox);
        }

        Gtk.CellRendererText renderer = (Gtk.CellRendererText) cell;
        renderer.markup = markup;
    }

    private inline Gtk.ListStore new_model() {
        return new Gtk.ListStore.newv(Column.get_types());
    }

    private bool on_match_selected(Gtk.TreeModel model, Gtk.TreeIter iter) {
        insert_address_at_cursor(iter);
        return true;
    }

    private bool on_cursor_on_match(Gtk.TreeModel model, Gtk.TreeIter iter) {
        this.last_iter = iter;
        return true;
    }

}
