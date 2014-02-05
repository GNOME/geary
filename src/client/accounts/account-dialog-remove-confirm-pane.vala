/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Confirmation of the deletion of an account
public class AccountDialogRemoveConfirmPane : AccountDialogPane {
    private Geary.AccountInformation? account = null;
    private Gtk.Label account_nickname_label;
    private Gtk.Label email_address_label;
    
    public signal void ok(Geary.AccountInformation? account);
    
    public signal void cancel();
    
    public AccountDialogRemoveConfirmPane(Gtk.Notebook notebook) {
        base(notebook);
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("remove_confirm.glade");
        pack_end((Gtk.Box) builder.get_object("container"));
        Gtk.ActionGroup actions = (Gtk.ActionGroup) builder.get_object("actions");
        account_nickname_label = (Gtk.Label) builder.get_object("account_nickname_label");
        email_address_label = (Gtk.Label) builder.get_object("email_address_label");
        
        // Hook up signals.
        actions.get_action("cancel_action").activate.connect(() => { cancel(); });
        actions.get_action("remove_action").activate.connect(() => { ok(account); });
    }
    
    public void set_account(Geary.AccountInformation a) {
        account = a;
        account_nickname_label.label = account.nickname;
        email_address_label.label = account.email;
    }
}

