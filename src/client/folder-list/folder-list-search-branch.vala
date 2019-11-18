/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * This branch is a top-level container for a search entry.
 */
public class FolderList.SearchBranch : Sidebar.RootOnlyBranch {
    public SearchBranch(Geary.SearchFolder folder) {
        base(new SearchEntry(folder));
    }

    public Geary.SearchFolder get_search_folder() {
        return (Geary.SearchFolder) ((SearchEntry) get_root()).folder;
    }
}

public class FolderList.SearchEntry : FolderList.AbstractFolderEntry {

    private int account_count = 0;

    public SearchEntry(Geary.SearchFolder folder) {
        base(folder);

        try {
            this.account_count = Geary.Engine.instance.get_accounts().size;
        } catch (GLib.Error error) {
            debug("Failed to get account count: %s", error.message);
        }

        Geary.Engine.instance.account_available.connect(on_accounts_changed);
        Geary.Engine.instance.account_unavailable.connect(on_accounts_changed);
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_TOTAL].connect(
            on_email_total_changed);
    }

    ~SearchEntry() {
        Geary.Engine.instance.account_available.disconnect(on_accounts_changed);
        Geary.Engine.instance.account_unavailable.disconnect(on_accounts_changed);
        folder.properties.notify[Geary.FolderProperties.PROP_NAME_EMAIL_TOTAL].disconnect(
            on_email_total_changed);
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

    private void on_accounts_changed() {
        sidebar_name_changed(get_sidebar_name());
        sidebar_tooltip_changed(get_sidebar_tooltip());

        try {
            this.account_count = Geary.Engine.instance.get_accounts().size;
        } catch (GLib.Error error) {
            debug("Failed to get account count: %s", error.message);
        }
    }

    private void on_email_total_changed() {
        sidebar_tooltip_changed(get_sidebar_tooltip());
    }

    public override int get_count() {
        return 0;
    }
}

