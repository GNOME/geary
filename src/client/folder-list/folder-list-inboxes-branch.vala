/* Copyright 2011-2012 Yorba Foundation
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
        base(new Sidebar.Grouping(_("Inboxes"), new ThemedIcon("mail-inbox")),
            Sidebar.Branch.Options.NONE, inbox_comparator);
    }
    
    private static int inbox_comparator(Sidebar.Entry a, Sidebar.Entry b) {
        assert(a is InboxFolderEntry);
        assert(b is InboxFolderEntry);
        
        InboxFolderEntry entry_a = (InboxFolderEntry) a;
        InboxFolderEntry entry_b = (InboxFolderEntry) b;
        return entry_a.position - entry_b.position;
    }
    
    public InboxFolderEntry? get_entry_for_account(Geary.Account account) {
        return folder_entries.get(account);
    }
    
    public void add_inbox(Geary.Folder inbox) {
        assert(inbox.get_special_folder_type() == Geary.SpecialFolderType.INBOX);
        
        InboxFolderEntry folder_entry = new InboxFolderEntry(inbox);
        graft(get_root(), folder_entry);
        
        folder_entries.set(inbox.account, folder_entry);
    }
    
    public void remove_inbox(Geary.Account account) {
        Sidebar.Entry? entry = folder_entries.get(account);
        if(entry == null) {
            debug("Could not remove inbox for %s", account.to_string());
            return;
        }
        
        prune(entry);
        folder_entries.unset(account);
    }
}
