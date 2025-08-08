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
internal class Accounts.EditorListPane : Accounts.EditorPane, CommandPane {


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
    internal override Application.CommandStack commands {
        get; protected set; default = new Application.CommandStack();
    }

    /** {@inheritDoc} */
    internal override bool is_operation_running { get; protected set; default = false; }

    /** {@inheritDoc} */
    internal override Cancellable? op_cancellable {
        get; protected set; default = null;
    }

    internal Manager accounts { get; private set; }

    /** {@inheritDoc} */
    protected override weak Accounts.Editor editor { get; set; }

    private bool show_welcome {
        get {
            return (this.accounts_list.get_row_at_index(0) == null);
        }
    }

    [GtkChild] private unowned Adw.HeaderBar header;

    [GtkChild] private unowned Gtk.Grid welcome_panel;

    [GtkChild] private unowned Gtk.Image welcome_icon;

    [GtkChild] private unowned Gtk.ListBox accounts_list;

    [GtkChild] private unowned Gtk.ScrolledWindow accounts_list_scrolled;

    private Gee.Map<Geary.AccountInformation,EditorEditPane> edit_pane_cache =
        new Gee.HashMap<Geary.AccountInformation,EditorEditPane>();


    public EditorListPane(Editor editor) {
        this.editor = editor;
        this.welcome_icon.icon_name = Config.APP_ID;

        // keep our own copy of this so we can disconnect from its signals
        // without worrying about the editor's lifecycle
        this.accounts = editor.accounts;

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

    public override void dispose() {
        this.commands.executed.disconnect(on_execute);
        this.commands.undone.disconnect(on_undo);
        this.commands.redone.disconnect(on_execute);
        disconnect_command_signals();

        this.accounts.account_added.disconnect(on_account_added);
    this.accounts.account_status_changed.disconnect(on_account_status_changed);
    this.accounts.account_removed.disconnect(on_account_removed);

    this.edit_pane_cache.clear();
    base.dispose();
    }

    internal void show_new_account() {
        this.editor.push_pane(new EditorAddPane(this.editor));
    }

    internal void show_existing_account(Geary.AccountInformation account) {
        EditorEditPane? edit_pane = this.edit_pane_cache.get(account);
        if (edit_pane == null) {
            edit_pane = new EditorEditPane(this.editor, account);
            this.edit_pane_cache.set(account, edit_pane);
        }
        this.editor.push_pane(edit_pane);
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

    private void add_account(Geary.AccountInformation account,
                             Manager.Status status) {
        AccountListRow row = new AccountListRow(account, status);
        row.moved.connect(on_account_row_moved);
        row.dropped.connect(on_editor_row_dropped);
        this.accounts_list.append(row);
    }

    private void update_welcome_panel() {
        if (this.show_welcome) {
            // No accounts are available, so show only the welcome
            // pane and service list.
            this.welcome_panel.show();
            this.accounts_list_scrolled.hide();
        } else {
            // There are some accounts available, so show them and
            // the full add service UI.
            this.welcome_panel.hide();
            this.accounts_list_scrolled.show();
        }
    }

    private AccountListRow? get_account_row(Geary.AccountInformation account) {
        for (int i = 0; true; i++) {
            unowned var row = this.accounts_list.get_row_at_index(i) as AccountListRow;
            if (row == null)
                break;
            if (row.account == account)
                return row;
        }
        return null;
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

    private void on_account_row_moved(AccountListRow source, int new_position) {
        this.commands.execute.begin(
            new ReorderAccountCommand(source, new_position, this.accounts),
            this.op_cancellable
        );
    }

    private void on_editor_row_dropped(AccountListRow source, AccountListRow target) {
        this.commands.execute.begin(
            new ReorderAccountCommand(
                source, target.get_index(), this.accounts
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
            var toast = new Adw.Toast(command.executed_label);
            toast.button_label = _("Undo");
            toast.action_name = Action.Edit.prefix(Action.Edit.UNDO);
            if (command.executed_notification_brief)
                toast.timeout = this.editor.application.config.brief_notification_duration;
            this.editor.add_toast(toast);
        }
    }

    private void on_undo(Application.Command command) {
        if (command.undone_label != null) {
            var toast = new Adw.Toast(command.undone_label);
            toast.button_label = _("Redo");
            toast.action_name = Action.Edit.prefix(Action.Edit.REDO);
            this.editor.add_toast(toast);
        }
    }

    [GtkCallback]
    private void on_row_activated(Gtk.ListBoxRow row) {
        unowned var account_row = row as AccountListRow;
        if (account_row == null)
            return;

        Manager manager = this.accounts;
        if (manager.is_goa_account(account_row.account) &&
            manager.get_status(account_row.account) != Manager.Status.ENABLED) {
            // GOA account but it's disabled, so just take people
            // directly to the GOA panel
            manager.show_goa_account.begin(
                account_row.account, this.op_cancellable,
                (obj, res) => {
                    try {
                        manager.show_goa_account.end(res);
                    } catch (GLib.Error err) {
                        // XXX display an error to the user
                        debug(
                            "Failed to show GOA account \"%s\": %s",
                            account_row.account.id,
                            err.message
                        );
                    }
                });
        } else {
            show_existing_account(account_row.account);
        }
    }

    [GtkCallback]
    private void on_add_button_clicked() {
        show_new_account();
    }
}


[GtkTemplate (ui = "/org/gnome/Geary/accounts-editor-account-list-row.ui")]
private class Accounts.AccountListRow : Adw.ActionRow {

    public Geary.AccountInformation account { get; construct set; }

    [GtkChild] private unowned Gtk.Image drag_icon;
    [GtkChild] private unowned Gtk.Image unavailable_icon;

    private bool drag_picked_up = false;
    private double drag_x;
    private double drag_y;

    public signal void moved(int new_position);
    public signal void dropped(AccountListRow target);

    construct {
        this.account.changed.connect(on_account_changed);
        update();
    }

    public AccountListRow(Geary.AccountInformation account,
                          Manager.Status status) {
        Object(account: account);
        update_status(status);
    }

    ~AccountListRow() {
        this.account.changed.disconnect(on_account_changed);
    }

    public void update() {
        string name = this.account.display_name;
        if (Geary.String.is_empty(name)) {
            name = account.primary_mailbox.to_address_display("", "");
        }
        this.title = name;

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
        this.subtitle = details;
    }

    public void update_status(Manager.Status status) {
        switch (status) {
        case ENABLED:
            remove_css_class("dim-label");
            this.tooltip_text = "";
            this.unavailable_icon.visible = false;
            break;

        case DISABLED:
            // Translators: Tooltip for accounts that have been
            // loaded but disabled by the user.
            this.tooltip_text = _("This account has been disabled");
            add_css_class("dim-label");
            this.unavailable_icon.visible = true;
            break;

        case UNAVAILABLE:
            // Translators: Tooltip for accounts that have been loaded but
            // because of some error are not able to be used.
            this.tooltip_text = _("This account has encountered a problem and is unavailable");
            add_css_class("dim-label");
            this.unavailable_icon.visible = true;
            break;

        case REMOVED:
            // Nothing to do - account is gone
            break;
        }

    }

    private void on_account_changed() {
        update();
        Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
        if (parent != null) {
            parent.invalidate_sort();
        }
    }

    [GtkCallback]
    private bool on_key_pressed(Gtk.EventControllerKey key_controller,
                                uint keyval,
                                uint keycode,
                                Gdk.ModifierType state) {
        if (state != Gdk.ModifierType.CONTROL_MASK)
            return Gdk.EVENT_PROPAGATE;

        int index = get_index();
        if (keyval == Gdk.Key.Up) {
            index--;
            if (index >= 0) {
                moved(index);
                return Gdk.EVENT_STOP;
            }
        } else if (keyval == Gdk.Key.Down) {
            index++;
            if (get_next_sibling() != null) {
                moved(index);
                return Gdk.EVENT_STOP;
            }
        }

        return Gdk.EVENT_PROPAGATE;
    }

    // DND

    [GtkCallback]
    private void on_drag_source_begin(Gtk.DragSource drag_source,
                                      Gdk.Drag drag) {

        // Show our row while dragging
        var drag_widget = new Gtk.ListBox();
        drag_widget.opacity = 0.8;

        Gtk.Allocation allocation;
        get_allocation(out allocation);
        drag_widget.set_size_request(allocation.width, allocation.height);

        var drag_row = new AccountListRow(this.account, Manager.Status.ENABLED);
        drag_widget.append(drag_row);
        drag_widget.drag_highlight_row(drag_row);

        var drag_icon = (Gtk.DragIcon) Gtk.DragIcon.get_for_drag(drag);
        drag_icon.child = drag_widget;
        drag.set_hotspot((int) this.drag_x, (int) this.drag_y);

        // Set a visual hint that the row is being dragged
        add_css_class("geary-drag-source");
        this.drag_picked_up = true;
    }

    [GtkCallback]
    private void on_drag_source_end(Gtk.DragSource drag_source,
                                    Gdk.Drag drag,
                                    bool delete_data) {
        remove_css_class("geary-drag-source");
        this.drag_picked_up = false;
    }

    [GtkCallback]
    private Gdk.ContentProvider on_drag_source_prepare(Gtk.DragSource drag_source,
                                                       double x,
                                                       double y) {
        Graphene.Point p = { (float) x, (float) y };
        Graphene.Point p_row;
        this.drag_icon.compute_point(this, p, out p_row);
        this.drag_x = p_row.x;
        this.drag_y = p_row.y;

        GLib.Value val = GLib.Value(typeof(int));
        val.set_int(get_index());
        return new Gdk.ContentProvider.for_value(val);
    }

    [GtkCallback]
    private Gdk.DragAction on_drop_target_enter(Gtk.DropTarget drop_target,
                                                double x,
                                                double y) {
        // Don't highlight the same row that was picked up
        if (!this.drag_picked_up) {
            Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
            if (parent != null) {
                parent.drag_highlight_row(this);
            }
        }

        return Gdk.DragAction.MOVE;
    }

    [GtkCallback]
    private void on_drop_target_leave(Gtk.DropTarget drop_target) {
        if (!this.drag_picked_up) {
            Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
            if (parent != null) {
                parent.drag_unhighlight_row();
            }
        }
    }

    [GtkCallback]
    private bool on_drop_target_drop(Gtk.DropTarget drop_target,
                                     GLib.Value val,
                                     double x,
                                     double y) {
        if (!val.holds(typeof(int))) {
            warning("Can't deal with non-int row value");
            return false;
        }

        int drag_index = val.get_int();
        Gtk.ListBox? parent = get_parent() as Gtk.ListBox;
        if (parent != null) {
            var drag_row = parent.get_row_at_index(drag_index) as AccountListRow;
            if (drag_row != null && drag_row != this) {
                drag_row.dropped(this);
                return true;
            }
        }

        return false;
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
