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

    private Manager accounts;

    private Application.CommandStack commands = new Application.CommandStack();

    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Overlay osd_overlay;

    [GtkChild]
    private Gtk.Grid pane_content;

    [GtkChild]
    private Gtk.Adjustment pane_adjustment;

    [GtkChild]
    private Gtk.Grid welcome_panel;

    [GtkChild]
    private Gtk.ListBox accounts_list;

    [GtkChild]
    private Gtk.Label add_service_label;

    [GtkChild]
    private Gtk.ListBox service_list;

    private Gee.Map<Geary.ServiceProvider,EditorAddPane> add_pane_cache =
        new Gee.HashMap<Geary.ServiceProvider,EditorAddPane>();

    private Gee.Map<Geary.AccountInformation,EditorEditPane> edit_pane_cache =
        new Gee.HashMap<Geary.AccountInformation,EditorEditPane>();


    public EditorListPane(Editor editor) {
        this.editor = editor;
        this.accounts =
            ((GearyApplication) editor.application).controller.account_manager;

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.accounts_list.set_header_func(Editor.seperator_headers);
        this.accounts_list.set_sort_func(ordinal_sort);
        foreach (Geary.AccountInformation account in this.accounts.iterable()) {
            add_account(account, this.accounts.get_status(account));
        }

        this.service_list.set_header_func(Editor.seperator_headers);
        this.service_list.add(new AddServiceProviderRow(Geary.ServiceProvider.GMAIL));
        this.service_list.add(new AddServiceProviderRow(Geary.ServiceProvider.OUTLOOK));
        this.service_list.add(new AddServiceProviderRow(Geary.ServiceProvider.YAHOO));
        this.service_list.add(new AddServiceProviderRow(Geary.ServiceProvider.OTHER));

        this.accounts.account_added.connect(on_account_added);
        this.accounts.account_status_changed.connect(on_account_status_changed);
        this.accounts.account_removed.connect(on_account_removed);

        this.commands.executed.connect(on_execute);
        this.commands.undone.connect(on_undo);
        this.commands.redone.connect(on_execute);

        update_welcome_panel();
    }

    public override void destroy() {
        this.commands.executed.disconnect(on_execute);
        this.commands.undone.disconnect(on_undo);
        this.commands.redone.disconnect(on_execute);

        this.accounts.account_added.disconnect(on_account_added);
        this.accounts.account_status_changed.disconnect(on_account_status_changed);
        this.accounts.account_removed.disconnect(on_account_removed);

        this.add_pane_cache.clear();
        this.edit_pane_cache.clear();
        base.destroy();
    }

    internal void show_add_account(Geary.ServiceProvider provider) {
        EditorAddPane? add_pane = this.add_pane_cache.get(provider);
        if (add_pane == null) {
            add_pane = new EditorAddPane(this.editor, provider);
            this.add_pane_cache.set(provider, add_pane);
        }
        this.editor.push(add_pane);
    }

    internal void show_existing_account(Geary.AccountInformation account) {
        EditorEditPane? edit_pane = this.edit_pane_cache.get(account);
        if (edit_pane == null) {
            edit_pane = new EditorEditPane(this.editor, account);
            this.edit_pane_cache.set(account, edit_pane);
        }
        this.editor.push(edit_pane);
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

    private void add_account(Geary.AccountInformation account,
                             Manager.Status status) {
        this.accounts_list.add(new AccountListRow(account, status));
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

    private void update_welcome_panel() {
        if (this.accounts_list.get_row_at_index(0) == null) {
            // No accounts are available, so show only the welcome
            // pane and service list.
            this.welcome_panel.show();
            this.accounts_list.hide();
            this.add_service_label.hide();
        } else {
            // There are some accounts available, so show them and
            // the full add service UI.
            this.welcome_panel.hide();
            this.accounts_list.show();
            this.add_service_label.show();
        }
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
                                  Manager.Status status) {
        add_account(account, status);
        update_welcome_panel();
    }

    private void on_account_status_changed(Geary.AccountInformation account,
                                           Manager.Status status) {
        AccountListRow? row = get_account_row(account);
        if (row != null) {
            row.update_status(status);
        }
    }

    private void on_account_removed(Geary.AccountInformation account) {
        AccountListRow? row = get_account_row(account);
        if (row != null) {
            this.accounts_list.remove(row);
            update_welcome_panel();
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
    private void on_row_activated(Gtk.ListBoxRow row) {
        EditorRow<EditorListPane>? setting = row as EditorRow<EditorListPane>;
        if (setting != null) {
            setting.activated(this);
        }
    }

    [GtkCallback]
    private bool on_list_keynav_failed(Gtk.Widget widget,
                                       Gtk.DirectionType direction) {
        bool ret = Gdk.EVENT_PROPAGATE;
        if (direction == Gtk.DirectionType.DOWN &&
            widget == this.accounts_list) {
            this.service_list.child_focus(direction);
            ret = Gdk.EVENT_STOP;
        } else if (direction == Gtk.DirectionType.UP &&
            widget == this.service_list) {
            this.accounts_list.child_focus(direction);
            ret = Gdk.EVENT_STOP;
        }
        return ret;
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
                          Manager.Status status) {
        this.account = account;

        this.account_name.show();
        this.account_name.set_hexpand(true);
        this.account_name.halign = Gtk.Align.START;

        this.account_details.show();

        this.layout.add(this.unavailable_icon);
        this.layout.add(this.account_name);
        this.layout.add(this.account_details);

        this.account.information_changed.connect(on_account_changed);
        update_nickname();
        update_status(status);
    }

    ~AccountListRow() {
        this.account.information_changed.disconnect(on_account_changed);
    }

    public override void activated(EditorListPane pane) {
        pane.show_existing_account(this.account);
    }

    public void update_nickname() {
        string name = this.account.nickname;
        if (Geary.String.is_empty(name)) {
            name = account.primary_mailbox.to_address_display("", "");
        }
        this.account_name.set_text(name);
    }

    public void update_status(Manager.Status status) {
        if (status != Manager.Status.UNAVAILABLE) {
            this.unavailable_icon.hide();
            this.set_tooltip_text("");
        } else {
            this.unavailable_icon.show();
            this.set_tooltip_text(
                _("This account has encountered a problem and is unavailable")
            );
        }

        string? details = this.account.service_label;
        switch (account.service_provider) {
        case Geary.ServiceProvider.GMAIL:
            details = _("Gmail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            details = _("Outlook.com");
            break;

        case Geary.ServiceProvider.YAHOO:
            details = _("Yahoo");
            break;
        }
        this.account_details.set_text(details);

        if (status == Manager.Status.ENABLED) {
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

    private void on_account_changed() {
        update_nickname();
    }

}


private class Accounts.AddServiceProviderRow : EditorRow<EditorListPane> {


    internal Geary.ServiceProvider provider;

    private Gtk.Label service_name = new Gtk.Label("");
    private Gtk.Image next_icon = new Gtk.Image.from_icon_name(
        "go-next-symbolic", Gtk.IconSize.SMALL_TOOLBAR
    );


    public AddServiceProviderRow(Geary.ServiceProvider provider) {
        this.provider = provider;

        // Translators: Label for adding a generic email account
        string? name = _("Other email provider");
        switch (provider) {
        case Geary.ServiceProvider.GMAIL:
            name = _("Gmail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            name = _("Outlook.com");
            break;

        case Geary.ServiceProvider.YAHOO:
            name = _("Yahoo");
            break;
        }
        this.service_name.set_text(name);
        this.service_name.set_hexpand(true);
        this.service_name.halign = Gtk.Align.START;
        this.service_name.show();

        this.next_icon.show();

        this.layout.add(this.service_name);
        this.layout.add(this.next_icon);
    }

    public override void activated(EditorListPane pane) {
        pane.show_add_account(this.provider);
    }

}


internal class Accounts.RemoveAccountCommand : Application.Command {


    private Geary.AccountInformation account;
    private Manager manager;


    public RemoveAccountCommand(Geary.AccountInformation account,
                                Manager manager) {
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
