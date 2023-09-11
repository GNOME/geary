/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class SearchBar : Hdy.SearchBar {

    /// Translators: Search entry placeholder text
    private const string DEFAULT_SEARCH_TEXT = _("Search");

    public Gtk.SearchEntry entry {
        get; private set; default = new Gtk.SearchEntry();
    }

    private Components.EntryUndo search_undo;
    private Geary.Account? current_account = null;
    private Geary.Engine engine;

    public signal void search_text_changed(string search_text);


    public SearchBar(Geary.Engine engine) {
        this.engine = engine;
        this.search_undo = new Components.EntryUndo(this.entry);

        this.notify["search-mode-enabled"].connect(on_search_mode_changed);

        /// Translators: Search entry tooltip
        this.entry.tooltip_text = _("Search all mail in account for keywords");
        this.entry.search_changed.connect(() => {
            search_text_changed(this.entry.text);
        });
        this.entry.activate.connect(() => {
            search_text_changed(this.entry.text);
        });
        this.entry.placeholder_text = DEFAULT_SEARCH_TEXT;
        this.entry.has_focus = true;

        var column = new Hdy.Clamp();
        column.maximum_size = 400;
        column.add(this.entry);

        connect_entry(this.entry);
        add(column);

        show_all();
    }

    public override void grab_focus() {
        set_search_mode(true);
        this.entry.grab_focus();
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
        this.entry.placeholder_text = (
            this.current_account == null || this.engine.accounts_count == 1
            ? DEFAULT_SEARCH_TEXT
            /// Translators: Search entry placeholder, string
            /// replacement is the name of an account
            : _("Search %s account").printf(
                this.current_account.information.display_name
            )
        );
    }

    private void on_search_mode_changed() {
        if (!this.search_mode_enabled) {
            this.search_undo.reset();
        }
    }
}
