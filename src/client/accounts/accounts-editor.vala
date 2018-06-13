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


    private const ActionEntry[] ACTION_ENTRIES = {
        { GearyController.ACTION_REDO, on_redo },
        { GearyController.ACTION_UNDO, on_undo },
    };


    internal static void seperator_headers(Gtk.ListBoxRow row,
                                           Gtk.ListBoxRow? first) {
        if (first == null) {
            row.set_header(null);
        } else if (row.get_header() == null) {
            row.set_header(new Gtk.Separator(Gtk.Orientation.HORIZONTAL));
        }
    }

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


    /** The command stack for this pane. */
    internal Application.CommandStack commands {
        get; private set; default = new Application.CommandStack();
    }

    /** The current account being edited, if any. */
    private Geary.AccountInformation selected_account {
        get; private set; default = null;
    }

    private AccountManager accounts;

    private SimpleActionGroup actions = new SimpleActionGroup();

    [GtkChild]
    private Gtk.HeaderBar default_header;

    [GtkChild]
    private Gtk.Stack editor_panes;

    [GtkChild]
    private Gtk.Button back_button;

    [GtkChild]
    private Gtk.Button undo_button;

    [GtkChild]
    private Gtk.Grid list_pane;

    [GtkChild]
    private Gtk.ListBox accounts_list;

    private Gee.LinkedList<Gtk.Widget> editor_pane_stack =
        new Gee.LinkedList<Gtk.Widget>();


    public Editor(GearyApplication application, Gtk.Window parent) {
        this.application = application;
        this.accounts = application.controller.account_manager;

        this.actions.add_action_entries(ACTION_ENTRIES, this);
        insert_action_group("win", this.actions);

        set_titlebar(this.default_header);
        set_transient_for(parent);
        //set_modal(true);
        set_modal(false);

        // XXX Glade 3.22 won't let us set this
        get_content_area().border_width = 2;

        this.accounts_list.set_header_func(seperator_headers);
        this.accounts_list.set_sort_func(ordinal_sort);

        this.editor_pane_stack.add(list_pane);

        foreach (Geary.AccountInformation account in accounts.iterable()) {
            add_account(account, accounts.get_status(account));
        }

        this.accounts_list.add(new AddRow());

        this.accounts.account_added.connect(on_account_added);
        this.accounts.account_status_changed.connect(on_account_status_changed);
        this.accounts.account_removed.connect(on_account_removed);

        this.commands.executed.connect(on_command);
        this.commands.undone.connect(on_command);
        this.commands.redone.connect(on_command);

        get_action(GearyController.ACTION_UNDO).set_enabled(false);
        get_action(GearyController.ACTION_REDO).set_enabled(false);
    }

    ~Editor() {
        this.commands.executed.disconnect(on_command);
        this.commands.undone.disconnect(on_command);
        this.commands.redone.disconnect(on_command);

        this.accounts.account_added.disconnect(on_account_added);
        this.accounts.account_status_changed.disconnect(on_account_status_changed);
        this.accounts.account_removed.disconnect(on_account_removed);
    }

    internal void push(Gtk.Widget child) {
        // Since keep old, already-popped panes around (see pop for
        // details), when a new pane is pushed on they need to be
        // truncated.
        Gtk.Widget current = this.editor_panes.get_visible_child();
        int target_length = this.editor_pane_stack.index_of(current) + 1;
        while (target_length < this.editor_pane_stack.size) {
            Gtk.Widget old = this.editor_pane_stack.remove_at(target_length);
            this.editor_panes.remove(old);
        }

        // Now push the new pane on
        this.editor_pane_stack.add(child);
        this.editor_panes.add(child);
        this.editor_panes.set_visible_child(child);
        this.back_button.show();
        this.undo_button.show();
    }

    internal void pop() {
        // One can't simply remove old panes fro the GTK stack since
        // there won't be any transition between them - the old one
        // will simply disappear. So we need to keep old, popped panes
        // around until a new one is pushed on.
        //
        // XXX work out a way to reuse the old ones if we go back to
        // them?
        Gtk.Widget current = this.editor_panes.get_visible_child();
        int next = this.editor_pane_stack.index_of(current) - 1;

        this.editor_panes.set_visible_child(this.editor_pane_stack.get(next));

        // Don't carry commands over from one pane to another
        this.commands.clear();
        get_action(GearyController.ACTION_UNDO).set_enabled(false);
        get_action(GearyController.ACTION_REDO).set_enabled(false);

        if (next == 0) {
            this.selected_account = null;
            this.back_button.hide();
            this.undo_button.hide();
        }
    }

    private void add_account(Geary.AccountInformation account,
                             AccountManager.Status status) {
        this.accounts_list.add(new AccountListRow(account, status));
    }

    private void show_account(Geary.AccountInformation account) {
        this.selected_account = account;
        push(new EditorEditPane(this, account));
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

    private inline GLib.SimpleAction get_action(string name) {
        return (GLib.SimpleAction) this.actions.lookup_action(name);
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

        if (this.selected_account == account) {
            while (this.editor_panes.get_visible_child() != this.list_pane) {
                pop();
            }
        }
    }

    private void on_undo() {
        this.commands.undo.begin(null);
    }

    private void on_redo() {
        this.commands.redo.begin(null);
    }

    private void on_command() {
        get_action(GearyController.ACTION_UNDO).set_enabled(
            this.commands.can_undo
        );
        get_action(GearyController.ACTION_REDO).set_enabled(
            this.commands.can_redo
        );

        Application.Command next_undo = this.commands.peek_undo();
        this.undo_button.set_tooltip_text(
            (next_undo != null && next_undo.undo_label != null)
            ? next_undo.undo_label : ""
        );
    }

    [GtkCallback]
    private void on_accounts_list_row_activated(Gtk.ListBoxRow activated) {
        AccountListRow? row = activated as AccountListRow;
        if (row != null) {
            show_account(row.account);
        }
    }

    [GtkCallback]
    private void on_back_button_clicked() {
        pop();
    }

}

private class Accounts.AccountListRow : EditorRow {


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
