/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for listing all known accounts.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_list_pane.ui")]
internal class Accounts.EditorListPane : Gtk.Grid, EditorPane, CommandPane {


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


    /** {@inheritDoc} */
    internal Gtk.Widget initial_widget {
        get {
            return this.accounts_list;
        }
    }

    /** {@inheritDoc} */
    internal Application.CommandStack commands {
        get; protected set; default = new Application.CommandStack();
    }

    /** {@inheritDoc} */
    internal bool is_operation_running { get; protected set; default = false; }

    /** {@inheritDoc} */
    internal GLib.Cancellable? op_cancellable {
        get; protected set; default = null;
    }

    internal Manager accounts { get; private set; }

    /** {@inheritDoc} */
    protected weak Accounts.Editor editor { get; set; }

    private bool show_welcome {
        get {
            return (this.accounts_list.get_row_at_index(0) == null);
        }
    }

    [GtkChild] private unowned Gtk.HeaderBar header;

    [GtkChild] private unowned Gtk.Grid pane_content;

    [GtkChild] private unowned Gtk.Adjustment pane_adjustment;

    [GtkChild] private unowned Gtk.Grid welcome_panel;

    [GtkChild] private unowned Gtk.Image welcome_icon;

    [GtkChild] private unowned Gtk.ListBox accounts_list;

    [GtkChild] private unowned Gtk.Frame accounts_list_frame;

    private Gee.Map<Geary.AccountInformation,EditorEditPane> edit_pane_cache =
        new Gee.HashMap<Geary.AccountInformation,EditorEditPane>();


    public EditorListPane(Editor editor) {
        this.editor = editor;
        this.welcome_icon.icon_name = Application.Client.APP_ID;

        // keep our own copy of this so we can disconnect from its signals
        // without worrying about the editor's lifecycle
        this.accounts = editor.accounts;

        this.pane_content.set_focus_vadjustment(this.pane_adjustment);

        this.accounts_list.set_header_func(Editor.seperator_headers);
        this.accounts_list.set_sort_func(ordinal_sort);
        foreach (Geary.AccountInformation account in this.accounts.iterable()) {
            add_account(account, this.accounts.get_status(account));
        }

        this.accounts.account_added.connect(on_account_added);
        this.accounts.account_status_changed.connect(on_account_status_changed);
        this.accounts.account_removed.connect(on_account_removed);

        this.commands.executed.connect(on_execute);
        this.commands.undone.connect(on_undo);
        this.commands.redone.connect(on_execute);
        connect_command_signals();
        update_welcome_panel();
    }

    public override void destroy() {
        this.commands.executed.disconnect(on_execute);
        this.commands.undone.disconnect(on_undo);
        this.commands.redone.disconnect(on_execute);
        disconnect_command_signals();

        this.accounts.account_added.disconnect(on_account_added);
        this.accounts.account_status_changed.disconnect(on_account_status_changed);
        this.accounts.account_removed.disconnect(on_account_removed);

        this.edit_pane_cache.clear();
        base.destroy();
    }

    internal void show_new_account() {
        this.editor.push(new EditorAddPane(this.editor));
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
                this.op_cancellable
            );
        }
    }

    /** {@inheritDoc} */
    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private void add_account(Geary.AccountInformation account,
                             Manager.Status status) {
        AccountListRow row = new AccountListRow(account, status);
        row.move_to.connect(on_editor_row_moved);
        row.dropped.connect(on_editor_row_dropped);
        this.accounts_list.add(row);
    }

    private void update_welcome_panel() {
        if (this.show_welcome) {
            // No accounts are available, so show only the welcome
            // pane and service list.
            this.welcome_panel.show();
            this.accounts_list_frame.hide();
        } else {
            // There are some accounts available, so show them and
            // the full add service UI.
            this.welcome_panel.hide();
            this.accounts_list_frame.show();
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

    private void on_editor_row_moved(EditorRow source, int new_position) {
        this.commands.execute.begin(
            new ReorderAccountCommand(
                (AccountListRow) source, new_position, this.accounts
            ),
            this.op_cancellable
        );
    }

    private void on_editor_row_dropped(EditorRow source, EditorRow target) {
        this.commands.execute.begin(
            new ReorderAccountCommand(
                (AccountListRow) source, target.get_index(), this.accounts
            ),
            this.op_cancellable
        );
    }

    private void on_account_removed(Geary.AccountInformation account) {
        AccountListRow? row = get_account_row(account);
        if (row != null) {
            this.accounts_list.remove(row);
            update_welcome_panel();
        }
    }

    private void on_execute(Application.Command command) {
        if (command.executed_label != null) {
            uint notification_time =
                Components.InAppNotification.DEFAULT_DURATION;
            if (command.executed_notification_brief) {
                notification_time =
                    this.editor.application.config.brief_notification_duration;
            }
            Components.InAppNotification ian = new Components.InAppNotification(
                command.executed_label, notification_time
            );
            ian.set_button(_("Undo"), Action.Edit.prefix(Action.Edit.UNDO));
            this.editor.add_notification(ian);
        }
    }

    private void on_undo(Application.Command command) {
        if (command.undone_label != null) {
            Components.InAppNotification ian =
                new Components.InAppNotification(command.undone_label);
            ian.set_button(_("Redo"), Action.Edit.prefix(Action.Edit.REDO));
            this.editor.add_notification(ian);
        }
    }

    [GtkCallback]
    private void on_row_activated(Gtk.ListBoxRow row) {
        EditorRow<EditorListPane>? setting = row as EditorRow<EditorListPane>;
        if (setting != null) {
            setting.activated(this);
        }
    }

    [GtkCallback]
    private void on_add_button_clicked() {
        show_new_account();
    }
}


private class Accounts.AccountListRow : AccountRow<EditorListPane,Gtk.Grid> {


    private Gtk.Label service_label = new Gtk.Label("");
    private Gtk.Image unavailable_icon = new Gtk.Image.from_icon_name(
        "dialog-warning-symbolic", Gtk.IconSize.BUTTON
    );

    public AccountListRow(Geary.AccountInformation account,
                          Manager.Status status) {
        base(account, "", new Gtk.Grid());
        enable_drag();

        this.value.add(this.unavailable_icon);
        this.value.add(this.service_label);

        this.service_label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR);
        this.service_label.set_line_wrap(true);
        this.service_label.show();

        this.account.changed.connect(on_account_changed);
        update();
        update_status(status);
    }

    ~AccountListRow() {
        this.account.changed.disconnect(on_account_changed);
    }

    public override void activated(EditorListPane pane) {
        Manager manager = pane.accounts;
        if (manager.is_goa_account(this.account) &&
            manager.get_status(this.account) != Manager.Status.ENABLED) {
            // GOA account but it's disabled, so just take people
            // directly to the GOA panel
            manager.show_goa_account.begin(
                account, pane.op_cancellable,
                (obj, res) => {
                    try {
                        manager.show_goa_account.end(res);
                    } catch (GLib.Error err) {
                        // XXX display an error to the user
                        debug(
                            "Failed to show GOA account \"%s\": %s",
                            account.id,
                            err.message
                        );
                    }
                });
        } else {
            pane.show_existing_account(this.account);
        }
    }

    public override void update() {
        string name = this.account.display_name;
        if (Geary.String.is_empty(name)) {
            name = account.primary_mailbox.to_address_display("", "");
        }
        this.label.set_text(name);

        string? details = this.account.service_label;
        switch (account.service_provider) {
        case Geary.ServiceProvider.GMAIL:
            details = _("Gmail");
            break;

        case Geary.ServiceProvider.OUTLOOK:
            details = _("Outlook.com");
            break;

        case Geary.ServiceProvider.OTHER:
            // no-op: Use the generated label
            break;
        }
        this.service_label.set_text(details);
    }

    public void update_status(Manager.Status status) {
        bool enabled = false;
        switch (status) {
        case ENABLED:
            enabled = true;
            this.set_tooltip_text("");
            break;

        case DISABLED:
            this.set_tooltip_text(
                // Translators: Tooltip for accounts that have been
                // loaded but disabled by the user.
                _("This account has been disabled")
            );
            break;

        case UNAVAILABLE:
            this.set_tooltip_text(
                // Translators: Tooltip for accounts that have been
                // loaded but because of some error are not able to be
                // used.
                _("This account has encountered a problem and is unavailable")
            );
            break;

        case REMOVED:
            // Nothing to do - account is gone
            break;
        }

        this.unavailable_icon.set_visible(!enabled);

        if (enabled) {
            this.label.get_style_context().remove_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
            this.service_label.get_style_context().remove_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
        } else {
            this.label.get_style_context().add_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
            this.service_label.get_style_context().add_class(
                Gtk.STYLE_CLASS_DIM_LABEL
            );
        }
    }

    private void on_account_changed() {
        update();
        Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
        if (parent != null) {
            parent.invalidate_sort();
        }
    }

}


internal class Accounts.ReorderAccountCommand : Application.Command {


    private AccountListRow source;
    private int source_index;
    private int target_index;

    private Manager manager;


    public ReorderAccountCommand(AccountListRow source,
                                 int target_index,
                                 Manager manager) {
        this.source = source;
        this.source_index = source.get_index();
        this.target_index = target_index;

        this.manager = manager;
    }

    public async override void execute(GLib.Cancellable? cancellable)
        throws GLib.Error {
        move_source(this.target_index);
    }

    public async override void undo(GLib.Cancellable? cancellable)
        throws GLib.Error {
        move_source(this.source_index);
    }

    private void move_source(int destination) {
        Gee.List<Geary.AccountInformation> accounts =
            this.manager.iterable().to_linked_list();
        accounts.sort(Geary.AccountInformation.compare_ascending);
        accounts.remove(this.source.account);
        accounts.insert(destination, this.source.account);

        int ord = 0;
        foreach (Geary.AccountInformation account in accounts) {
            if (account.ordinal != ord) {
                account.ordinal = ord;
                account.changed();
            }
            ord++;
        }

        this.source.grab_focus();
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
        this.executed_label = _("Account “%s” removed").printf(
            account.display_name
        );

        // Translators: Notification shown after removing an account
        // is undone. The string substitution is the name of the
        // account.
        this.undone_label = _("Account “%s” restored").printf(
            account.display_name
        );
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
