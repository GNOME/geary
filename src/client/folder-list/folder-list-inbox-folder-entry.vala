/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A FolderEntry for inboxes in the Inboxes branch.
public class FolderList.InboxFolderEntry : FolderList.FolderEntry {
    public InboxFolderEntry(Geary.Folder folder) {
        base(folder);
        folder.account.information.notify["nickname"].connect(on_nicknamed_changed);
    }
    
    ~InboxFolderEntry() {
        folder.account.information.notify["nickname"].disconnect(on_nicknamed_changed);
    }
    
    public override string get_sidebar_name() {
        return folder.account.information.nickname;
    }
    
    public Geary.AccountInformation get_account_information() {
        return folder.account.information;
    }
    
    private void on_nicknamed_changed() {
        sidebar_name_changed(folder.account.information.nickname);
    }
}

