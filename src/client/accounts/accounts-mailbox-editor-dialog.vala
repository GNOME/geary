/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A simple dialog that allows adding/editing Mailboxes (e.g. when configuring
 * sender addresses).
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts-mailbox-editor-dialog.ui")]
internal class Accounts.MailboxEditorDialog : Adw.Dialog {


    [GtkChild] private unowned Adw.EntryRow name_row;
    [GtkChild] private unowned Adw.EntryRow address_row;
    [GtkChild] private unowned Gtk.Button apply_button;
    [GtkChild] private unowned Gtk.Button remove_button;
    private Components.EmailValidator address_validator;

    private bool changed = false;


    /** The display name for the address */
    public string display_name { get; construct set; default = ""; }

    /** The raw email address */
    public string address { get; construct set; default = ""; }


    /** Fired if the user pressed "Add"/"Apply" with the new details */
    public signal void apply(Geary.RFC822.MailboxAddress mailbox);

    /** Fired if the user requested to remove the address */
    public signal void remove();


    static construct {
        install_action("apply", null, (Gtk.WidgetActionActivateFunc) action_apply);
        install_action("remove", null, (Gtk.WidgetActionActivateFunc) action_remove);
    }


    construct {
        this.name_row.text = this.display_name;
        this.address_row.text = this.address;
        this.changed = false;

        this.address_validator =
            new Components.EmailValidator(this.address_row);
        this.address_validator.changed.connect((validator) => {
            action_set_enabled("add", this.changed && input_is_valid());
        });
    }


    /**
     * Creates a MailboxEditorDialog for creating a new mailbox.
     * @param display_name A suggestion for the name
     */
    public MailboxEditorDialog.for_new(string? display_name) {
        Object(
            display_name: display_name ?? "",
            address: ""
        );

        // Cange "Apply" to "Add" in this case, since that matches better
        this.apply_button.label = _("_Add");

        // Can't remove an address that doesn't exist yet
        action_set_enabled("remove", false);
    }

    public MailboxEditorDialog.for_existing(Geary.RFC822.MailboxAddress mailbox,
                                            bool can_remove) {
        Object(
            display_name: mailbox.name ?? "",
            address: mailbox.address
        );

        action_set_enabled("remove", can_remove);
    }

    [GtkCallback]
    private void on_name_changed(Gtk.Editable editable) {
        var new_name = this.name_row.text.strip();
        if (new_name != this.display_name) {
            this.display_name = new_name;
            this.changed = true;
        }
    }

    [GtkCallback]
    private void on_address_changed(Gtk.Editable editable) {
        this.address = this.address_row.text.strip();
        var new_address = this.address_row.text.strip();
        if (new_address != this.address) {
            this.address = new_address;
            this.changed = true;
        }
    }

    [GtkCallback]
    private void on_entry_activate() {
        activate_action("add", null);
    }

    private bool input_is_valid() {
        return this.address_validator.state == Components.Validator.Validity.INDETERMINATE
            || this.address_validator.is_valid;
    }

    private void action_apply(string action_name, Variant? param) {
        if (!input_is_valid()) {
            debug("Tried to add mailbox, but email was invalid");
            return;
        }

        apply(
            new Geary.RFC822.MailboxAddress(this.display_name, this.address)
        );
    }

    private void action_remove(string action_name, Variant? param) {
        remove();
    }
}
