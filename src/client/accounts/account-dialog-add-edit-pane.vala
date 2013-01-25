/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Add or edit an account.  Used with AccountDialog.
public class AccountDialogAddEditPane : Gtk.Box {
    public AddEditPage add_edit_page { get; private set; default = new AddEditPage(); }
    private Gtk.ButtonBox button_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
    private Gtk.Button ok_button = new Gtk.Button.from_stock(Gtk.Stock.ADD);
    private Gtk.Button cancel_button = new Gtk.Button.from_stock(Gtk.Stock.CANCEL);
    
    public signal void ok(Geary.AccountInformation info);
    
    public signal void cancel();
    
    public signal void size_changed();
    
    public AccountDialogAddEditPane() {
        Object(orientation: Gtk.Orientation.VERTICAL, spacing: 4);
        
        add_edit_page.show_welcome(false);
        button_box.set_layout(Gtk.ButtonBoxStyle.END);
        button_box.expand = false;
        button_box.spacing = 6;
        button_box.pack_start(cancel_button, false, false, 0);
        button_box.pack_start(ok_button, false, false, 0);
        ok_button.can_default = true;
        
        // Since we're not yet in a window, we have to wait before setting the default action.
        realize.connect(() => { ok_button.has_default = true; });
        
        ok_button.clicked.connect(on_ok);
        cancel_button.clicked.connect(() => { cancel(); });
        
        add_edit_page.size_changed.connect(() => { size_changed(); } );
        
        pack_start(add_edit_page);
        pack_start(button_box);
    }
    
    private void on_ok() {
        ok(add_edit_page.get_account_information());
    }
}

