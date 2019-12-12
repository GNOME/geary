/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class SearchBar : Gtk.SearchBar {
    private const string DEFAULT_SEARCH_TEXT = _("Search");

    public string search_text { get { return search_entry.text; } }
    public bool search_entry_has_focus { get { return search_entry.has_focus; } }

    private Gtk.SearchEntry search_entry = new Gtk.SearchEntry();
    private Components.EntryUndo search_undo;
    private Geary.Account? current_account = null;

    public signal void search_text_changed(string search_text);

    public SearchBar() {
        // Search entry.
        search_entry.width_chars = 28;
        search_entry.tooltip_text = _("Search all mail in account for keywords (Ctrl+S)");
        search_entry.search_changed.connect(() => {
            search_text_changed(search_entry.text);
        });
        search_entry.activate.connect(() => {
            search_text_changed(search_entry.text);
        });
        search_entry.has_focus = true;

        this.search_undo = new Components.EntryUndo(this.search_entry);

        this.notify["search-mode-enabled"].connect(on_search_mode_changed);

        add(search_entry);

        set_search_placeholder_text(DEFAULT_SEARCH_TEXT);
    }

    public void set_search_text(string text) {
        this.search_entry.text = text;
    }

    public void give_search_focus() {
        set_search_mode(true);
        search_entry.grab_focus();
    }

    public void set_search_placeholder_text(string placeholder) {
        search_entry.placeholder_text = placeholder;
    }

    public void set_account(Geary.Account? account) {
        if (current_account != null) {
            current_account.information.changed.disconnect(
                on_information_changed
            );
        }

        if (account != null) {
            account.information.changed.connect(
                on_information_changed
            );
        }

        current_account = account;

        on_information_changed(); // Set new account name.
    }

    private void on_information_changed() {
        var main = get_toplevel() as Application.MainWindow;
        if (main != null) {
            set_search_placeholder_text(
                current_account == null ||
                main.application.engine.accounts_count == 1
                ? DEFAULT_SEARCH_TEXT :
                _("Search %s account").printf(
                    current_account.information.display_name
                )
            );
        }
    }

    private void on_search_mode_changed() {
        if (!this.search_mode_enabled) {
            this.search_undo.reset();
        }
    }
}
