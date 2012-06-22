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
    
    protected override Geary.SpecialFolderType get_special_folder_type_for_path(Geary.FolderPath path) {
        return Geary.SpecialFolderType.NONE;
    }
    
    public override bool delete_is_archive() {
        return false;
    }
}

