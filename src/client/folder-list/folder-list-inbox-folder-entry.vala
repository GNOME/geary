/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// A FolderEntry for inboxes in the Inboxes branch.
public class FolderList.InboxFolderEntry : FolderList.FolderEntry {
    private static int total_inbox_folders = 0;
    
    public int position { get; private set; }
    
    public InboxFolderEntry(Geary.Folder folder) {
        base(folder);
        position = total_inbox_folders++;
    }
    
    public override string get_sidebar_name() {
        return folder.account.information.nickname;
    }
}
