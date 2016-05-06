/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class SearchBar : Gtk.SearchBar {
    private const string ICON_CLEAR_NAME = "edit-clear-symbolic";
    private const string ICON_CLEAR_RTL_NAME = "edit-clear-rtl-symbolic";
    private const string DEFAULT_SEARCH_TEXT = _("Search");
    
    public string search_text { get { return search_entry.text; } }
    public bool search_entry_has_focus { get { return search_entry.has_focus; } }
    
    private Gtk.SearchEntry search_entry = new Gtk.SearchEntry();
    private Geary.ProgressMonitor? search_upgrade_progress_monitor = null;
    private MonitoredProgressBar search_upgrade_progress_bar = new MonitoredProgressBar();
    private Geary.Account? current_account = null;
    
    public signal void search_text_changed(string search_text);
    
    public SearchBar() {
        // Search entry.
        search_entry.width_chars = 28;
        search_entry.tooltip_text = _("Search all mail in account for keywords (Ctrl+S)");
        search_entry.changed.connect(on_search_entry_changed);
        search_entry.key_press_event.connect(on_search_key_press);
        on_search_entry_changed(); // set initial state
        search_entry.has_focus = true;
        
        // Search upgrade progress bar.
        search_upgrade_progress_bar.show_text = true;
        search_upgrade_progress_bar.visible = false;
        search_upgrade_progress_bar.no_show_all = true;
        
        add(search_upgrade_progress_bar);
        add(search_entry);
        
        set_search_placeholder_text(DEFAULT_SEARCH_TEXT);
        
        GearyApplication.instance.controller.account_selected.connect(on_account_changed);
    }
    
    public void set_search_text(string text) {
        search_entry.text = text;
    }
    
    public void give_search_focus() {
        set_search_mode(true);
        search_entry.grab_focus();
    }
    
    public void set_search_placeholder_text(string placeholder) {
        search_entry.placeholder_text = placeholder;
    }
    
    private void on_search_entry_changed() {
        search_text_changed(search_entry.text);
        // Enable/disable clear button.
        search_entry.secondary_icon_name = search_entry.text != "" ?
            (get_direction() == Gtk.TextDirection.RTL ? ICON_CLEAR_RTL_NAME : ICON_CLEAR_NAME) : null;
    }
    
    private bool on_search_key_press(Gdk.EventKey event) {
        // Clear box if user hits escape.
        if (Gdk.keyval_name(event.keyval) == "Escape")
            search_entry.text = "";
        
        // Force search if user hits enter.
        if (Gdk.keyval_name(event.keyval) == "Return")
            on_search_entry_changed();
        
        return false;
    }
    
    private void on_search_upgrade_start() {
        // Set the progress bar's width to match the search entry's width.
        int minimum_width = 0;
        int natural_width = 0;
        search_entry.get_preferred_width(out minimum_width, out natural_width);
        search_upgrade_progress_bar.width_request = minimum_width;
        
        search_entry.hide();
        search_upgrade_progress_bar.show();
    }
    
    private void on_search_upgrade_finished() {
        search_entry.show();
        search_upgrade_progress_bar.hide();
    }
    
    private void on_account_changed(Geary.Account? account) {
        on_search_upgrade_finished(); // Reset search box.
        
        if (search_upgrade_progress_monitor != null) {
            search_upgrade_progress_monitor.start.disconnect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.disconnect(on_search_upgrade_finished);
            search_upgrade_progress_monitor = null;
        }
        
        if (current_account != null) {
            current_account.information.notify[Geary.AccountInformation.PROP_NICKNAME].disconnect(
                on_nickname_changed);
        }
        
        if (account != null) {
            search_upgrade_progress_monitor = account.search_upgrade_monitor;
            search_upgrade_progress_bar.set_progress_monitor(search_upgrade_progress_monitor);
            
            search_upgrade_progress_monitor.start.connect(on_search_upgrade_start);
            search_upgrade_progress_monitor.finish.connect(on_search_upgrade_finished);
            if (search_upgrade_progress_monitor.is_in_progress)
                on_search_upgrade_start(); // Remove search box, we're already in progress.
            
            account.information.notify[Geary.AccountInformation.PROP_NICKNAME].connect(
                on_nickname_changed);
            
            search_upgrade_progress_bar.text = _("Indexing %s account").printf(account.information.nickname);
        }
        
        current_account = account;
        
        on_nickname_changed(); // Set new account name.
    }
    
    private void on_nickname_changed() {
        set_search_placeholder_text(current_account == null ||
            GearyApplication.instance.controller.get_num_accounts() == 1 ? DEFAULT_SEARCH_TEXT :
            _("Search %s account").printf(current_account.information.nickname));
    }
}
