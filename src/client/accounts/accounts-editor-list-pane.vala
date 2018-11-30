/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for listing all known accounts.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_list_pane.ui")]
internal class Accounts.EditorListPane : Gtk.Grid, EditorPane {


    private static int ordinal_sort(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
        AccountListRow? account_a = a as AccountListRow;
        AccountListRow? account_b = b as AccountListRow;

        if (account_a == null) {
            return (account_b == null) ? 0 : 1;
        } else if (account_b == null) {
            return -1;
        }

        return Geary.AccountInformation.compare_ascending(
            account_a.account, account_b.account
        );
    }


    protected weak Accounts.Editor editor { get; set; }

    private AccountManager accounts { get; private set; }

    private Application.CommandStack commands {
        get; private set; default = new Application.CommandStack();
    }

    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Overlay osd_overlay;

    [GtkChild]
    private Gtk.ListBox accounts_list;

    private Gee.Map<Geary.AccountInformation,EditorEditPane> edit_pane_cache =
        new Gee.HashMap<Geary.AccountInformation,EditorEditPane>();


    public EditorListPane(Editor editor) {
        this.editor = editor;
        this.accounts =
            ((GearyApplication) editor.application).controller.account_manager;

        this.accounts_list.set_header_func(Editor.seperator_headers);
        this.accounts_list.set_sort_func(ordinal_sort);

        foreach (Geary.AccountInformation account in this.accounts.iterable()) {
            add_account(account, this.accounts.get_status(account));
        }

        this.accounts_list.add(new AddRow<EditorServersPane>());

        this.accounts.account_added.connect(on_account_added);
        this.accounts.account_status_changed.connect(on_account_status_changed);
        this.accounts.account_removed.connect(on_account_removed);

        this.commands.executed.connect(on_execute);
        this.commands.undone.connect(on_undo);
        this.commands.redone.connect(on_execute);
    }

    public override void destroy() {
        this.commands.executed.disconnect(on_execute);
        this.commands.undone.disconnect(on_undo);
        this.commands.redone.disconnect(on_execute);

        this.accounts.account_added.disconnect(on_account_added);
        this.accounts.account_status_changed.disconnect(on_account_status_changed);
        this.accounts.account_removed.disconnect(on_account_removed);

        this.edit_pane_cache.clear();
        base.destroy();
    }

    /** Adds a new account to the list. */
    internal void add_account(Geary.AccountInformation account,
                             AccountManager.Status status) {
        this.accounts_list.add(new AccountListRow(account, status));
    }

    /** Removes an account from the list. */
    internal void remove_account(Geary.AccountInformation account) {
        AccountListRow? row = get_account_row(account);
        if (row != null) {
            this.commands.execute.begin(
                new RemoveAccountCommand(account, this.accounts),
                null
            );
        }
    }

    internal void pane_shown() {
        update_actions();
    }

    internal void undo() {
        this.commands.undo.begin(null);
    }

    internal void redo() {
        this.commands.redo.begin(null);
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private void add_notification(InAppNotification notification) {
        this.osd_overlay.add_overlay(notification);
        notification.show();
    }

    private void update_actions() {
        this.editor.get_action(GearyController.ACTION_UNDO).set_enabled(
            this.commands.can_undo
        );
        this.editor.get_action(GearyController.ACTION_REDO).set_enabled(
            this.commands.can_redo
        );
    }

    private AccountListRow? get_account_row(Geary.AccountInformation account) {
        AccountListRow? row = null;
        this.accounts_list.foreach((child) => {
                AccountListRow? account_row = child as AccountListRow;
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
        AccountListRow? row = get_account_row(account);
        if (row != null) {
            row.update(status);
        }
    }

    private void on_account_removed(Geary.AccountInformation account) {
        AccountListRow? row = get_account_row(account);
        if (row != null) {
            this.accounts_list.remove(row);
        }
    }

    private void on_execute(Application.Command command) {
        InAppNotification ian = new InAppNotification(command.executed_label);
        ian.set_button(_("Undo"), "win." + GearyController.ACTION_UNDO);
        add_notification(ian);

        update_actions();
    }

    private void on_undo(Application.Command command) {
        InAppNotification ian = new InAppNotification(command.undone_label);
        ian.set_button(_("Redo"), "win." + GearyController.ACTION_REDO);
        add_notification(ian);

        update_actions();
    }

    [GtkCallback]
    private void on_accounts_list_row_activated(Gtk.ListBoxRow activated) {
        AccountListRow? row = activated as AccountListRow;
        if (row != null) {
            Geary.AccountInformation account = row.account;
            EditorEditPane? edit_pane = this.edit_pane_cache.get(account);
            if (edit_pane == null) {
                edit_pane = new EditorEditPane(this.editor, account);
                this.edit_pane_cache.set(account, edit_pane);
            }
            this.editor.push(edit_pane);
        }
    }

}


private class Accounts.AccountListRow : EditorRow<EditorListPane> {


    internal Geary.AccountInformation account;

    private Gtk.Image unavailable_icon = new Gtk.Image.from_icon_name(
        "dialog-warning-symbolic", Gtk.IconSize.BUTTON
    );
    private Gtk.Label account_name = new Gtk.Label("");
    private Gtk.Label account_details = new Gtk.Label("");


    public AccountListRow(Geary.AccountInformation account,
                          AccountManager.Status status) {
        this.account = account;

        this.account_name.show();
        this.account_name.set_hexpand(true);
        this.account_name.halign = Gtk.Align.START;

        this.account_details.show();

        this.layout.add(this.unavailable_icon);
        this.layout.add(this.account_name);
        this.layout.add(this.account_details);

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


internal class Accounts.RemoveAccountCommand : Application.Command {


    private Geary.AccountInformation account;
    private AccountManager manager;


    public RemoveAccountCommand(Geary.AccountInformation account,
                                AccountManager manager) {
        this.account = account;
        this.manager = manager;

        // Translators: Notification shown after removing an
        // account. The string substitution is the name of the
        // account.
        this.executed_label = _("Account “%s” removed").printf(account.nickname);

        // Translators: Notification shown after removing an account
        // is undone. The string substitution is the name of the
        // account.
        this.undone_label = _("Account “%s” restored").printf(account.nickname);
    }

    public async override void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.manager.remove_account(this.account, cancellable);
    }

    public async override void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        yield this.manager.restore_account(this.account, cancellable);
    }

}
