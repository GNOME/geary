/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.OtherAccount : Geary.GenericImapAccount {
    public OtherAccount(string name, string username, AccountInformation account_info,
        File user_data_dir, Imap.Account remote, Sqlite.Account local) {
        base (name, username, account_info, user_data_dir, remote, local);
    }
    
    protected override GenericImapFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        Sqlite.Account local_account, Sqlite.Folder local_folder) {
        return new OtherFolder(this, remote_account, local_account, local_folder,
            (path.basename == Imap.Account.INBOX_NAME) ? SpecialFolderType.INBOX : SpecialFolderType.NONE);
    }
}

