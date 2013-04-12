/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OtherAccount : Geary.ImapEngine.GenericAccount {
    public OtherAccount(string name, AccountInformation account_information,
        Imap.Account remote, ImapDB.Account local) {
        base (name, account_information, remote, local);
    }
    
    protected override GenericFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        return new OtherFolder(this, remote_account, local_account, local_folder,
            (path.basename == Imap.Account.INBOX_NAME) ? SpecialFolderType.INBOX : SpecialFolderType.NONE);
    }
}

