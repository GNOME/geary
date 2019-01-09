/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for removing an account from the client.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_remove_pane.ui")]
internal class Accounts.EditorRemovePane : Gtk.Grid, EditorPane, AccountPane {


    /** {@inheritDoc} */
    internal weak Accounts.Editor editor { get; set; }

    /** {@inheritDoc} */
    internal Geary.AccountInformation account { get ; protected set; }

    /** {@inheritDoc} */
    internal Gtk.Widget initial_widget {
        get { return this.remove_button; }
    }

    /** {@inheritDoc} */
    internal bool is_operation_running { get; protected set; default = false; }

    /** {@inheritDoc} */
    internal GLib.Cancellable? op_cancellable {
        get; protected set; default = null;
    }

    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Label warning_label;

    [GtkChild]
    private Gtk.Button remove_button;


    public EditorRemovePane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        this.warning_label.set_text(
            this.warning_label.get_text().printf(account.display_name)
        );

        connect_account_signals();
    }

    ~EditorRemovePane() {
        disconnect_account_signals();
    }

    /** {@inheritDoc} */
    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    [GtkCallback]
    private void on_remove_button_clicked() {
        this.editor.remove_account(this.account);
    }

    [GtkCallback]
    private void on_back_button_clicked() {
        this.editor.pop();
    }

}
