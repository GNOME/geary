/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Add or edit an account.  Used with AccountDialog.
public class AccountDialogAddEditPane : AccountDialogPane {
    public AddEditPage add_edit_page { get; private set; default = new AddEditPage(); }
    private Gtk.ButtonBox button_box = new Gtk.ButtonBox(Gtk.Orientation.HORIZONTAL);
    private Gtk.Button ok_button = new Gtk.Button.with_mnemonic(Stock._OK);
    private Gtk.Button cancel_button = new Gtk.Button.with_mnemonic(Stock._CANCEL);
    
    public signal void ok(Geary.AccountInformation info);
    
    public signal void cancel();
    
    public signal void size_changed();
    
    public AccountDialogAddEditPane(Gtk.Stack stack) {
        base(stack);
        
        button_box.set_layout(Gtk.ButtonBoxStyle.END);
        button_box.expand = false;
        button_box.spacing = 6;
        button_box.pack_start(cancel_button, false, false, 0);
        button_box.pack_start(ok_button, false, false, 0);
        ok_button.can_default = true;
        
        add_edit_page.info_changed.connect(on_info_changed);
        
        // Since we're not yet in a window, we have to wait before setting the default action.
        realize.connect(() => { ok_button.has_default = true; });
        
        ok_button.clicked.connect(on_ok);
        cancel_button.clicked.connect(() => { cancel(); });
        
        add_edit_page.size_changed.connect(() => { size_changed(); } );
        
        pack_start(add_edit_page);
        pack_start(button_box, false, false);
        
        // Default mode is Welcome.
        set_mode(AddEditPage.PageMode.WELCOME);
    }
    
    public void set_mode(AddEditPage.PageMode mode) {
        ok_button.label = (mode == AddEditPage.PageMode.EDIT) ? _("_Save") : _("_Add");
        add_edit_page.set_mode(mode);
    }
    
    public AddEditPage.PageMode get_mode() {
        return add_edit_page.get_mode();
    }
    
    public void set_account_information(Geary.AccountInformation info,
        Geary.Engine.ValidationResult result = Geary.Engine.ValidationResult.OK) {
        add_edit_page.set_account_information(info, result);
    }
    
    public void set_validation_result(Geary.Engine.ValidationResult result) {
        add_edit_page.set_validation_result(result);
    }
    
    public void reset_all() {
        add_edit_page.reset_all();
    }
    
    private void on_ok() {
        ok(add_edit_page.get_account_information());
    }
    
    public override void present() {
        base.present();
        add_edit_page.update_ui();
        on_info_changed();
    }
    
    private void on_info_changed() {
        ok_button.has_default = ok_button.sensitive = add_edit_page.is_complete();
    }
}

