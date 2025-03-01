/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/accounts-mailbox-editor-dialog.ui")]
internal class Accounts.MailboxEditorDialog : Adw.Dialog {


    public string display_name { get; set; }

    public string address { get; set; }

    [GtkChild] private unowned Adw.EntryRow name_row;
    [GtkChild] private unowned Adw.EntryRow address_row;
    [GtkChild] private unowned Gtk.Button remove_button;
    private Components.EmailValidator address_validator;

    public signal void activated();
    public signal void remove_clicked();


    public MailboxEditorDialog(string? display_name,
                               string? address,
                               bool can_remove) {
        Object(
            display_name: display_name,
            address: address
        );

        this.name_row.text = display_name ?? "";
        this.address_row.text = address ?? "";

        this.address_validator =
            new Components.EmailValidator(this.address_row);

        this.remove_button.visible = can_remove;
    }

    [GtkCallback]
    private void on_name_changed(Gtk.Editable editable) {
        this.display_name = this.name_row.text.strip();
    }

    [GtkCallback]
    private void on_address_changed(Gtk.Editable editable) {
        this.address = this.address_row.text.strip();
    }

    [GtkCallback]
    private void on_remove_clicked() {
        remove_clicked();
    }

    [GtkCallback]
    private void on_entry_activate() {
        if (this.address_validator.state == Components.Validator.Validity.INDETERMINATE || this.address_validator.is_valid) {
            activated();
        }
    }

}
