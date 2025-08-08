/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2025 Niels De Graef <nielsdegraef@gmail.com>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A widget that allows a user to create a list of email addresses
 * (for example a "CC" row).
 *
 *XXX we need to put an EntryUndo back here
 */
public class Composer.AddressesRow : Adw.EntryRow, Geary.BaseInterface {

    /**
     * The list of email addresses.
     *
     * Check the "is-valid" property to see if they are actually valid.
     *
     * Manually setting this property will override any text that was there before.
     */
    public Geary.RFC822.MailboxAddresses addresses {
        get { return this._addresses; }
        set {
            this._addresses = value;
            validate_addresses();
            this.text = value.to_full_display();
        }
    }
    private Geary.RFC822.MailboxAddresses _addresses = new Geary.RFC822.MailboxAddresses();

    /** Determines if the entry contains only valid email addresses (and is not empty) */
    public bool is_valid { get; private set; default = false; }

    public bool is_empty {
        //XXX could this be this.text.length != 0 insteaD?
        get { return this.addresses.is_empty; }
    }

    // Text between the start of the entry or end of the previous email
    // address and the current position of the cursor, if any.
    // This will be used for searching a match in the contact list.
    //XXX maybe replace this with a filter?
    public string search_key {
        get { return this._search_key; }
        set {
            if (this._search_key == value)
                return;
            string old_value = this._search_key;
            this._search_key = value;
            update_search_filter(old_value, value);
            notify_property("search-key");
        }
    }
    private string _search_key = "";

    // The list of (possibly incomplete) email addresses
    private GenericArray<string> addresses_raw = new GenericArray<string>();
    // Index in addressew_raw of the email address the cursor is currently at
    private int cursor_at_address = 0;

    public Application.ContactStore? contacts { get; set; default = null; }

    private unowned AddressSuggestionPopover popover;

    static construct {
        set_css_name("geary-composer-widget-header-row");
    }

    construct {
        this.changed.connect(on_changed);

        var popover = new AddressSuggestionPopover();
        bind_property("contacts", popover, "contacts", BindingFlags.SYNC_CREATE);
        popover.selected_address.connect(on_address_suggestion_selected);
        popover.set_parent(this);
        this.popover = popover;

        // We can't use the default autohide behavior since it grabs focus,
        // which we don't want (as the user should be able to continue typing).
        popover.autohide = false;
    }

    public AddressesRow(string title) {
        Object(title: title);
        base_ref();
    }

    ~AddressesRow() {
        base_unref();
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
        update_addresses();
        update_validity();
    }

    private void update_addresses() {
        string current_key = "";
        this.cursor_at_address = 0;
        this.addresses_raw.length = 0;

        // NB: Do not strip any white space from the addresses,
        // otherwise we won't be able to accurately insert
        // addresses in the middle of the list in
        // ::insert_address_at_cursor.

        int current_char = 0;
        unichar c = 0;
        int start_idx = 0;
        int next_idx = 0;
        bool in_quote = false;
        while (this.text.get_next_char(ref next_idx, out c)) {
            if (current_char == (this.text.char_count() - 1) &&
                current_char != 0) {
                if (c != ',') {
                    // Strip whitespace here though so it does not
                    // interfere with search and highlighting.
                    current_key = this.text.slice(
                        start_idx, next_idx
                    ).strip();
                }
                // We're in the middle of the address, so it
                // hasn't yet been added to the list and hence we
                // don't need to subtract 1 from its size here
                this.cursor_at_address = this.addresses_raw.length;
            }

            switch (c) {
            case ',':
                if (!in_quote) {
                    // Don't include the comma in the address
                    string address = this.text.slice(start_idx, next_idx - 1);
                    this.addresses_raw.add(address);
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
        string address = this.text.substring(start_idx);
        this.addresses_raw.add(address);

        // XXX we probably want to do this with a timeout
        // Update current key
        this.search_key = current_key;
    }

    private void update_validity() {
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

        //XXX we should make this conditional
        notify_property("addresses");
        notify_property("is-valid");
        notify_property("is-empty");
    }

    private void update_search_filter(string old_value, string new_value) {
        if (this.contacts == null)
            return;

        if (new_value.length > 3) {
            this.popover.search_contacts.begin(new_value, null, (obj, res) => {
                this.popover.search_contacts.end(res);
            });
        } else {
            this.popover.clear_suggestions();
        }
    }

    private void on_address_suggestion_selected(AddressSuggestionPopover popover,
                                                Geary.RFC822.MailboxAddress address) {
        insert_address_at_cursor(address);
    }

    private void insert_address_at_cursor(Geary.RFC822.MailboxAddress mailbox) {
        // Take care to do a delete then an insert here so that
        // Component.EntryUndo can combine the two into a single
        // undoable command.

        int start_char = 0;
        if (this.cursor_at_address > 0) {
            // Address parts don't contain commas, so need to add
            // an char width for it. Don't need to worry about
            // spaces because they are preserved by
            // ::update_addresses.
            start_char++;
            for (uint i = 0; i < this.cursor_at_address; i++) {
                start_char += this.addresses_raw[i].char_count();
            }
        }
        int end_char = get_position();

        // Format and use the selected address
        string formatted = mailbox.to_full_display();
        if (this.cursor_at_address != 0) {
            // Isn't the first address, so add some whitespace to
            // pad it out
            formatted = " " + formatted;
        }
        if (get_position() < this.text.char_count() &&
            this.addresses_raw[this.cursor_at_address].strip() !=
            this.search_key.strip()) {
            // Isn't at the end of the entry, and the address
            // under the cursor does not simply consist of the
            // lookup key (i.e. is effectively already empty
            // otherwise), so add a comma to separate this address
            // from the next one
            formatted = formatted + ", ";
        }
        this.addresses_raw.insert(this.cursor_at_address, formatted);

        // Update the entry text
        if (start_char < end_char) {
            delete_text(start_char, end_char);
        }
        insert_text(formatted, -1, ref start_char);

        // Update the entry cursor position. The previous call
        // updates the start so just use that, but add extra space
        // for the comma and any white space at the start of the
        // next address.
        if (start_char < this.text.char_count()) {
            start_char += 2;
        }
        set_position(start_char);
    }
}

/**
 * A helper object to list not just the addresses but also their related contact
 */
public class ContactAddressItem : GLib.Object {
    public Application.Contact contact { get; construct set; }
    public Geary.RFC822.MailboxAddress address { get; construct set; }

    public ContactAddressItem(Application.Contact contact,
                              Geary.RFC822.MailboxAddress address) {
        Object(contact: contact, address: address);
    }
}

public class AddressSuggestionPopover : Gtk.Popover {

    // Minimum visibility for the contact to appear in autocompletion.
    private const Geary.Contact.Importance VISIBILITY_THRESHOLD =
        Geary.Contact.Importance.RECEIVED_FROM;

    public Application.ContactStore contacts { get; construct set; }

    private GLib.ListStore model;
    private Gtk.SingleSelection selection;

    /**
     * Fired when the user has selected an address suggestion
     */
    public signal void selected_address(Geary.RFC822.MailboxAddress address);

    construct {
        var factory = new Gtk.SignalListItemFactory();
        factory.setup.connect(on_setup_item);
        factory.bind.connect(on_bind_item);

        this.model = new GLib.ListStore(typeof(ContactAddressItem));
        this.model.items_changed.connect((model, pos, removed, added) => {
            bool is_empty = (model.get_n_items() == 0);
            bool was_empty = ((model.get_n_items() - added + removed) == 0);
            if (is_empty != was_empty) {
                if (was_empty)
                    popup();
                else
                    popdown();
            }
        });
        this.selection = new Gtk.SingleSelection(this.model);

        var listview = new Gtk.ListView(selection, factory);
        listview.single_click_activate = true;
        listview.tab_behavior = Gtk.ListTabBehavior.ITEM;
        listview.activate.connect(on_activate);

        var sw = new Gtk.ScrolledWindow();
        sw.hscrollbar_policy = Gtk.PolicyType.NEVER;
        sw.propagate_natural_height = true;
        sw.max_content_height = 300;
        sw.child = listview;
        this.child = sw;
    }

    private void on_setup_item(Object object) {
        unowned var item = (Gtk.ListItem) object;

        // Create the row widget
        var row = new AddressSuggestionRow();
        item.child = row;
    }

    private void on_bind_item(Object object) {
        unowned var item = (Gtk.ListItem) object;
        unowned var row = (AddressSuggestionRow) item.child;
        unowned var contact_address = (ContactAddressItem) item.item;

        row.contact_address = contact_address;
    }

    private void on_activate(Gtk.ListView listvieww,
                             uint position) {
        var contact_addr = (ContactAddressItem?) this.selection.selected_item;
        if (contact_addr == null)
            return;

        popdown();
        selected_address(contact_addr.address);
    }

    public void clear_suggestions() {
        model.remove_all();
    }

    public async void search_contacts(string query,
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
            model.remove_all();
            foreach (Application.Contact contact in results) {
                for (uint i = 0; i < contact.email_addresses.get_n_items(); i++) {
                    var addr = (Geary.RFC822.MailboxAddress) contact.email_addresses.get_item(i);
                    model.append(new ContactAddressItem(contact, addr));
                }
            }
        }
    }
}

private class AddressSuggestionRow : Gtk.Box {

    private unowned Adw.Avatar avatar;
    private unowned Gtk.Label name_label;
    private unowned Gtk.Label address_label;

    public ContactAddressItem? contact_address {
        get { return this._contact_address; }
        set {
            if (this._contact_address == value)
                return;

            update(value);
            notify_property("contact-address");
        }
    }
    private ContactAddressItem? _contact_address = null;

    construct {
        this.orientation = Gtk.Orientation.HORIZONTAL;
        this.spacing = 6;
        this.margin_top = 3;
        this.margin_bottom = 3;
        this.margin_start = 3;
        this.margin_end = 3;

        add_css_class("contact-address-list-row");

        var avatar = new Adw.Avatar(32, null, true);
        append(avatar);
        this.avatar = avatar;

        var names_vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 3);
        append(names_vbox);

        var label = new Gtk.Label("");
        label.ellipsize = Pango.EllipsizeMode.END;
        label.valign = Gtk.Align.CENTER;
        label.halign = Gtk.Align.START;
        label.xalign = 0;
        label.width_chars = 24;
        names_vbox.append(label);
        this.name_label = label;

        label = new Gtk.Label("");
        label.ellipsize = Pango.EllipsizeMode.END;
        label.valign = Gtk.Align.CENTER;
        label.halign = Gtk.Align.START;
        label.xalign = 0;
        label.width_chars = 24;
        names_vbox.append(label);
        this.address_label = label;
    }

    private void update(ContactAddressItem contact_addr) {
        this._contact_address = contact_addr;

        if (contact_addr == null) {
            this.avatar.text = null;
            this.name_label.label = "";
            this.address_label.label = "";
            return;
        }

        //XXX GTK4
        if (Geary.String.is_empty(contact_addr.contact.display_name)) {
            this.avatar.text = null;
            this.name_label.label = "";
            this.name_label.visible = false;
        } else {
            this.avatar.text = contact_addr.contact.display_name;
            this.name_label.label = contact_addr.contact.display_name;
            this.name_label.visible = true;
        }
        this.address_label.label = contact_addr.address.address;
    }
}
