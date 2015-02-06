/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OtherAccount : Geary.ImapEngine.GenericAccount {
    public OtherAccount(string name, AccountInformation account_information,
        Imap.Account remote, ImapDB.Account local) {
        base (name, account_information, false, remote, local);
    }
    
    protected override MinimalFolder new_folder(Geary.FolderPath path, Imap.Account remote_account,
        ImapDB.Account local_account, ImapDB.Folder local_folder) {
        SpecialFolderType type;
        if (Imap.MailboxSpecifier.folder_path_is_inbox(path))
            type = SpecialFolderType.INBOX;
        else
            type = local_folder.get_properties().attrs.get_special_folder_type();
        
        return new OtherFolder(this, remote_account, local_account, local_folder, type);
    }
}

