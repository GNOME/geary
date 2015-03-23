/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class AccountDialogEditAlternateEmailsPane : AccountDialogPane {
    private class ListItem : Gtk.Label {
        public Geary.RFC822.MailboxAddress mailbox;
        
        public ListItem(Geary.RFC822.MailboxAddress mailbox) {
            this.mailbox = mailbox;
            
            label = "<b>%s</b>".printf(Geary.HTML.escape_markup(mailbox.get_full_address()));
            use_markup = true;
            ellipsize = Pango.EllipsizeMode.END;
            GtkUtil.set_label_xalign(this, 0.0f);
        }
    }
    
    public string? email { get; private set; default = null; }
    
    public bool changed { get; private set; default = false; }
    
    private Gtk.Label title_label;
    private Gtk.Entry email_entry;
    private Gtk.Button add_button;
    private Gtk.ListBox address_listbox;
    private Gtk.ToolButton delete_button;
    private Gtk.Button cancel_button;
    private Gtk.Button update_button;
    private ListItem? selected_item = null;
    
    private Geary.AccountInformation? account_info = null;
    private Geary.RFC822.MailboxAddress? primary_mailbox = null;
    private Gee.HashSet<Geary.RFC822.MailboxAddress> mailboxes = new Gee.HashSet<Geary.RFC822.MailboxAddress>();
    
    public signal void done();
    
    public AccountDialogEditAlternateEmailsPane(Gtk.Stack stack) {
        base (stack);
        
        Gtk.Builder builder = GearyApplication.instance.create_builder("edit_alternate_emails.glade");
        
        // Primary container
        pack_start((Gtk.Widget) builder.get_object("container"));
        
        title_label = (Gtk.Label) builder.get_object("title_label");
        email_entry = (Gtk.Entry) builder.get_object("email_entry");
        add_button = (Gtk.Button) builder.get_object("add_button");
        address_listbox = (Gtk.ListBox) builder.get_object("address_listbox");
        delete_button = (Gtk.ToolButton) builder.get_object("delete_button");
        cancel_button = (Gtk.Button) builder.get_object("cancel_button");
        update_button = (Gtk.Button) builder.get_object("update_button");
        
        // Clear text when the secondary icon (not always available) is pressed
        email_entry.icon_release.connect((pos) => {
            if (pos == Gtk.EntryIconPosition.SECONDARY)
                email_entry.text = "";
        });
        
        email_entry.bind_property("text", add_button, "sensitive", BindingFlags.SYNC_CREATE,
            transform_email_to_sensitive);
        email_entry.notify["text-length"].connect(on_email_entry_text_length_changed);
        bind_property("changed", update_button, "sensitive", BindingFlags.SYNC_CREATE);
        
        delete_button.sensitive = false;
        
        address_listbox.row_selected.connect(on_row_selected);
        add_button.clicked.connect(on_add_clicked);
        delete_button.clicked.connect(on_delete_clicked);
        cancel_button.clicked.connect(() => { done(); });
        update_button.clicked.connect(on_update_clicked);
    }
    
    private bool validate_address_text(string email_address, out Geary.RFC822.MailboxAddress? parsed) {
        parsed = null;
        
        Geary.RFC822.MailboxAddresses mailboxes = new Geary.RFC822.MailboxAddresses.from_rfc822_string(
            email_address);
        if (mailboxes.size != 1)
            return false;
        
        Geary.RFC822.MailboxAddress mailbox = mailboxes.get(0);
        
        if (!mailbox.is_valid())
            return false;
        
        if (Geary.String.stri_equal(mailbox.address, primary_mailbox.address))
            return false;
        
        if (Geary.String.is_empty(mailbox.address))
            return false;
        
        parsed = mailbox;
        
        return true;
    }
    
    private bool transform_email_to_sensitive(Binding binding, Value source, ref Value target) {
        Geary.RFC822.MailboxAddress? parsed;
        target = validate_address_text(email_entry.text, out parsed) && !mailboxes.contains(parsed);
        
        return true;
    }
    
    private void on_email_entry_text_length_changed() {
        bool has_text = email_entry.text_length != 0;
        
        email_entry.secondary_icon_name = has_text ? "edit-clear-symbolic" : null;
        email_entry.secondary_icon_sensitive = has_text;
        email_entry.secondary_icon_activatable = has_text;
    }
    
    public void set_account(Geary.AccountInformation account_info) {
        this.account_info = account_info;
        
        email = account_info.email;
        primary_mailbox = account_info.get_primary_mailbox_address();
        mailboxes.clear();
        changed = false;
        
        // reset/clear widgets
        title_label.label = _("Additional addresses for %s").printf(account_info.email);
        email_entry.text = "";
        
        // clear listbox
        foreach (Gtk.Widget widget in address_listbox.get_children())
            address_listbox.remove(widget);
        
        // Add all email addresses; add_email_address() silently drops the primary address
        foreach (Geary.RFC822.MailboxAddress mailbox in account_info.get_all_mailboxes())
            add_mailbox(mailbox, false);
    }
    
    public override void present() {
        base.present();
        
        // because in a Gtk.Stack, need to do this manually after presenting
        email_entry.grab_focus();
        add_button.has_default = true;
    }
    
    private void add_mailbox(Geary.RFC822.MailboxAddress mailbox, bool is_change) {
        if (mailboxes.contains(mailbox) || primary_mailbox.equal_to(mailbox))
            return;
        
        mailboxes.add(mailbox);
        
        ListItem item = new ListItem(mailbox);
        item.show_all();
        address_listbox.add(item);
        
        if (is_change)
            changed = true;
    }
    
    private void remove_mailbox(Geary.RFC822.MailboxAddress address) {
        if (!mailboxes.remove(address))
            return;
        
        foreach (Gtk.Widget widget in address_listbox.get_children()) {
            Gtk.ListBoxRow row = (Gtk.ListBoxRow) widget;
            ListItem item = (ListItem) row.get_child();
            
            if (item.mailbox.equal_to(address)) {
                address_listbox.remove(widget);
                
                changed = true;
                
                break;
            }
        }
    }
    
    private void on_row_selected(Gtk.ListBoxRow? row) {
        selected_item = (row != null) ? (ListItem) row.get_child() : null;
        delete_button.sensitive = (selected_item != null);
    }
    
    private void on_add_clicked() {
        Geary.RFC822.MailboxAddress? parsed;
        if (!validate_address_text(email_entry.text, out parsed) || parsed == null)
            return;
        
        add_mailbox(parsed, true);
        
        // reset state for next input
        email_entry.text = "";
        email_entry.grab_focus();
        add_button.has_default = true;
    }
    
    private void on_delete_clicked() {
        if (selected_item != null)
            remove_mailbox(selected_item.mailbox);
    }
    
    private void on_update_clicked() {
        account_info.replace_alternate_mailboxes(mailboxes);
        
        done();
    }
}

