/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The main account editor window.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor.ui")]
public class Accounts.Editor : Gtk.Dialog {


    private static int ordinal_sort(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
        AccountRow? account_a = a as AccountRow;
        AccountRow? account_b = b as AccountRow;

        if (account_a == null) {
            return (account_b == null) ? 0 : 1;
        } else if (account_b == null) {
            return -1;
        }

        return Geary.AccountInformation.compare_ascending(
            account_a.account, account_b.account
        );
    }

    private static void update_header(Gtk.ListBoxRow row, Gtk.ListBoxRow? first) {
        if (first == null) {
            row.set_header(null);
        } else if (row.get_header() == null) {
            row.set_header(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
        }
    }

    private AccountManager accounts;

    [GtkChild]
    private Gtk.ListBox accounts_list;


    public Editor(AccountManager accounts, Gtk.Window parent) {
        this.accounts = accounts;
        set_transient_for(parent);

        this.accounts_list.set_header_func(update_header);
        this.accounts_list.set_sort_func(ordinal_sort);

        foreach (Geary.AccountInformation account in accounts.iterable()) {
            add_account(account, accounts.get_status(account));
        }

        this.accounts_list.add(new AddRow());

        accounts.account_added.connect(on_account_added);
        accounts.account_status_changed.connect(on_account_status_changed);
        accounts.account_removed.connect(on_account_removed);
    }

    ~Editor() {
        this.accounts.account_added.disconnect(on_account_added);
        this.accounts.account_status_changed.disconnect(on_account_status_changed);
        this.accounts.account_removed.disconnect(on_account_removed);
    }

    private void add_account(Geary.AccountInformation account,
                             AccountManager.Status status) {
        this.accounts_list.add(new AccountRow(account, status));
    }

    private AccountRow? get_account_row(Geary.AccountInformation account) {
        AccountRow? row = null;
        this.accounts_list.foreach((child) => {
                AccountRow? account_row = child as AccountRow;
                if (account_row != null && account_row.account == account) {
                    row = account_row;
                }
            });
        return row;
    }

    private void on_account_added(Geary.AccountInformation account,
                                  AccountManager.Status status) {
        add_account(account, status);
    }

    private void on_account_status_changed(Geary.AccountInformation account,
                                           AccountManager.Status status) {
        AccountRow? row = get_account_row(account);
        if (row != null) {
            row.update(status);
        }
    }

    private void on_account_removed(Geary.AccountInformation account) {
        AccountRow? row = get_account_row(account);
        if (row != null) {
            this.accounts_list.remove(row);
        }
    }

}

private class Accounts.AccountRow : Gtk.ListBoxRow {


    public Geary.AccountInformation account;

    private Gtk.Image unavailable_icon = new Gtk.Image.from_icon_name(
        "dialog-warning-symbolic", Gtk.IconSize.BUTTON
    );
    private Gtk.Label account_name = new Gtk.Label("");
    private Gtk.Label account_details = new Gtk.Label("");


    public AccountRow(Geary.AccountInformation account,
                      AccountManager.Status status) {
        this.account = account;
        get_style_context().add_class("geary-settings");

        this.unavailable_icon.no_show_all = true;

        this.account_name.set_hexpand(true);
        this.account_name.halign = Gtk.Align.START;

        Gtk.Grid layout = new Gtk.Grid();
        layout.orientation = Gtk.Orientation.HORIZONTAL;
        layout.add(this.unavailable_icon);
        layout.add(this.account_name);
        layout.add(this.account_details);

        add(layout);

        update(status);
    }

    public void update(AccountManager.Status status) {
        if (status != AccountManager.Status.UNAVAILABLE) {
            this.unavailable_icon.hide();
            this.set_tooltip_text("");
        } else {
            this.unavailable_icon.show();
            this.set_tooltip_text(
                _("This account has encountered a problem and is unavailable")
            );
        }

        string name = this.account.nickname;
        if (Geary.String.is_empty(name)) {
            name = account.primary_mailbox.to_address_display("", "");
        }
        this.account_name.set_text(name);

        string? details = this.account.service_label;
        switch (account.service_provider) {
        case Geary.ServiceProvider.GMAIL:
            details = _("GMail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            details = _("Outlook.com");
            break;

        case Geary.ServiceProvider.YAHOO:
            details = _("Yahoo");
            break;
        }
        this.account_details.set_text(details);

        if (status == AccountManager.Status.ENABLED) {
            this.account_name.get_style_context().remove_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
            this.account_details.get_style_context().remove_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
        } else {
            this.account_name.get_style_context().add_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
            this.account_details.get_style_context().add_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
        }
    }

}

private class Accounts.AddRow : Gtk.ListBoxRow {


    public AddRow() {
        get_style_context().add_class("geary-settings");

        Gtk.Image add_icon = new Gtk.Image.from_icon_name(
            "list-add-symbolic", Gtk.IconSize.BUTTON
        );
        add_icon.set_hexpand(true);

        Gtk.Grid layout = new Gtk.Grid();
        layout.orientation = Gtk.Orientation.HORIZONTAL;

        layout.add(add_icon);

        add(layout);
    }


}
