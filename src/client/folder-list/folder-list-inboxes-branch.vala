/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A special branch that sits before the accounts branches, containing only
// the inboxes for all accounts.
public class FolderList.InboxesBranch : Sidebar.Branch {
    public Gee.HashMap<Geary.Account, InboxFolderEntry> folder_entries {
        get; private set; default = new Gee.HashMap<Geary.Account, InboxFolderEntry>(); }

    public InboxesBranch() {
        base(
            new Sidebar.Header(_("Inboxes")),
            STARTUP_OPEN_GROUPING,
            inbox_comparator
        );
    }

    private static int inbox_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        assert(a is InboxFolderEntry);
        assert(b is InboxFolderEntry);

        InboxFolderEntry entry_a = (InboxFolderEntry) a;
        InboxFolderEntry entry_b = (InboxFolderEntry) b;
        return Geary.AccountInformation.compare_ascending(entry_a.get_account_information(),
            entry_b.get_account_information());
    }

    public InboxFolderEntry? get_entry_for_account(Geary.Account account) {
        return folder_entries.get(account);
    }

    public void add_inbox(Application.FolderContext inbox) {
        InboxFolderEntry folder_entry = new InboxFolderEntry(inbox);
        graft(get_root(), folder_entry);

        folder_entries.set(inbox.folder.account, folder_entry);
        inbox.folder.account.information.notify["ordinal"].connect(on_ordinal_changed);
    }

    public void remove_inbox(Geary.Account account) {
        Sidebar.Entry? entry = folder_entries.get(account);
        if(entry == null) {
            debug("Could not remove inbox for %s", account.to_string());
            return;
        }

        account.information.notify["ordinal"].disconnect(on_ordinal_changed);
        prune(entry);
        folder_entries.unset(account);
    }

    private void on_ordinal_changed() {
        reorder_all();
    }
}
