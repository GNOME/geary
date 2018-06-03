/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The main account editor window.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_edit_pane.ui")]
public class Accounts.EditorEditPane : Gtk.Grid {


    private Geary.AccountInformation account;

    [GtkChild]
    private Gtk.ListBox details_list;

    [GtkChild]
    private Gtk.ListBox addresses_list;

    [GtkChild]
    private Gtk.ScrolledWindow signature_scrolled;

    private ClientWebView signature_preview;

    [GtkChild]
    private Gtk.ListBox settings_list;


    public EditorEditPane(GearyApplication application,
                          Geary.AccountInformation account) {
        this.account = account;

        PropertyRow nickname_row = new PropertyRow(
            account,
            "nickname",
            // Translators: This label in the account editor is for
            // the user's name for an account.
            _("Account name")
        );
        nickname_row.set_dim_label(true);

        this.details_list.set_header_func(Editor.seperator_headers);
        this.details_list.add(nickname_row);

        this.addresses_list.set_header_func(Editor.seperator_headers);
        this.addresses_list.add(
            new AddressRow(account.primary_mailbox, get_login_session_name())
        );

        string? default_name = account.primary_mailbox.name;
        if (Geary.String.is_empty_or_whitespace(default_name)) {
            default_name = null;
        }
        if (account.alternate_mailboxes != null) {
            foreach (Geary.RFC822.MailboxAddress alt
                     in account.alternate_mailboxes) {
                this.addresses_list.add(new AddressRow(alt, default_name));
            }
        }

        this.addresses_list.add(new AddRow());

        this.signature_preview = new ClientWebView(application.config);
        this.signature_preview.load_html(account.email_signature);
        this.signature_preview.show();

        this.signature_scrolled.add(this.signature_preview);

        this.settings_list.set_header_func(Editor.seperator_headers);
        // No settings to show at the moment, so hide the list and its
        // frame until we do.
        this.settings_list.get_parent().hide();
    }

    private string? get_login_session_name() {
        string? name = Environment.get_real_name();
        if (Geary.String.is_empty(name) || name == "Unknown") {
            name = null;
        }
        return name;
    }

}


private class Accounts.PropertyRow : LabelledEditorRow {


    private GLib.Object object;
    private string property_name;

    private Gtk.Label value = new Gtk.Label("");


    public PropertyRow(Object object,
                       string property_name,
                       string label) {
        base(label);

        this.object = object;
        this.property_name = property_name;

        this.value.show();
        this.layout.add(this.value);

        update();
    }

    public void update() {
        string? value = null;
        this.object.get(this.property_name, ref value);

        if (value != null) {
            this.value.set_text(value);
        }
    }

}


private class Accounts.AddressRow : LabelledEditorRow {


    private Geary.RFC822.MailboxAddress address;
    private string? fallback_name;

    private Gtk.Label value = new Gtk.Label("");


    public AddressRow(Geary.RFC822.MailboxAddress address,
                      string? fallback_name) {
        base("");
        this.address = address;
        this.fallback_name = fallback_name;

        this.value.show();
        this.layout.add(this.value);

        update();
    }

    public void update() {
        string? name = Geary.String.is_empty_or_whitespace(this.address.name)
            ? this.fallback_name
            : this.address.name;

        if (Geary.String.is_empty_or_whitespace(name)) {
            name = _("No name set");
            set_dim_label(true);
        } else {
            set_dim_label(false);
        }

        this.label.set_text(name);
        this.value.set_text(this.address.address.strip());
    }

}
