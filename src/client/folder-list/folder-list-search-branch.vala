/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * This branch is a top-level container for a search entry.
 */
public class FolderList.SearchBranch : Sidebar.RootOnlyBranch {
    public SearchBranch(Geary.App.SearchFolder folder, Geary.Engine engine) {
        base(new SearchEntry(folder, engine));
    }

    public Geary.App.SearchFolder get_search_folder() {
        return (Geary.App.SearchFolder) ((SearchEntry) get_root()).folder;
    }
}

public class FolderList.SearchEntry : FolderList.AbstractFolderEntry {

    Geary.Engine engine;
    private int account_count = 0;

    public SearchEntry(Geary.App.SearchFolder folder,
                       Geary.Engine engine) {
        base(folder);
        this.engine = engine;

        try {
            this.account_count = engine.get_accounts().size;
        } catch (GLib.Error error) {
            debug("Failed to get account count: %s", error.message);
        }

        this.engine.account_available.connect(on_accounts_changed);
        this.engine.account_unavailable.connect(on_accounts_changed);
        folder.properties.notify[
            Geary.FolderProperties.PROP_NAME_EMAIL_TOTAL
        ].connect(on_email_total_changed);
    }

    ~SearchEntry() {
        this.engine.account_available.disconnect(on_accounts_changed);
        this.engine.account_unavailable.disconnect(on_accounts_changed);
        folder.properties.notify[
            Geary.FolderProperties.PROP_NAME_EMAIL_TOTAL
        ].disconnect(on_email_total_changed);
    }

    public override string get_sidebar_name() {
        return this.account_count == 1
        ? _("Search")
        : _("Search %s account").printf(folder.account.information.display_name);
    }

    public override string? get_sidebar_tooltip() {
        int total = folder.properties.email_total;
        return ngettext("%d result", "%d results", total).printf(total);
    }

    public override string? get_sidebar_icon() {
        return "edit-find-symbolic";
    }

    public override string to_string() {
        return "SearchEntry: " + folder.to_string();
    }

    private void on_accounts_changed(Geary.Engine engine,
                                     Geary.AccountInformation config) {
        entry_changed();
        try {
            this.account_count = engine.get_accounts().size;
        } catch (GLib.Error error) {
            debug("Failed to get account count: %s", error.message);
        }
    }

    private void on_email_total_changed() {
        entry_changed();
    }

    public override int get_count() {
        return 0;
    }
}
