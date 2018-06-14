/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An account editor pane for removing an account from the client.
 */
[GtkTemplate (ui = "/org/gnome/Geary/accounts_editor_remove_pane.ui")]
internal class Accounts.EditorRemovePane : Gtk.Grid, EditorPane, AccountPane {


    internal Geary.AccountInformation account { get ; protected set; }

    protected weak Accounts.Editor editor { get; set; }

    [GtkChild]
    private Gtk.HeaderBar header;

    [GtkChild]
    private Gtk.Stack confirm_stack;

    [GtkChild]
    private Gtk.Label warning_label;

    [GtkChild]
    private Gtk.Spinner remove_spinner;

    [GtkChild]
    private Gtk.Label remove_label;

    [GtkChild]
    private Gtk.Button remove_button;


    public EditorRemovePane(Editor editor, Geary.AccountInformation account) {
        this.editor = editor;
        this.account = account;

        this.warning_label.set_text(
            this.warning_label.get_text().printf(account.nickname)
        );
        this.remove_label.set_text(
            this.remove_label.get_text().printf(account.nickname)
        );

        this.account.information_changed.connect(on_account_changed);
        update_header();
    }

    ~EditorRemovePane() {
        this.account.information_changed.disconnect(on_account_changed);
    }

    internal Gtk.HeaderBar get_header() {
        return this.header;
    }

    private void on_account_changed() {
        update_header();
    }

    [GtkCallback]
    private void on_remove_button_clicked() {
        this.remove_button.set_sensitive(false);
        this.remove_spinner.start();
        this.confirm_stack.set_visible_child_name("remove");
    }

    [GtkCallback]
    private void on_back_button_clicked() {
        this.editor.pop();
    }

}
