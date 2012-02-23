/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.OtherAccount : Geary.GenericImapAccount {
    public OtherAccount(string name, string username, AccountInformation account_info,
        File user_data_dir, RemoteAccount remote,
        LocalAccount local) {
        base (name, username, account_info, user_data_dir, remote, local);
    }
    
    public override string get_user_folders_label() {
        return _("Folders");
    }
    
    public override Geary.SpecialFolderMap? get_special_folder_map() {
        return null;
    }
    
    public override Gee.Set<Geary.FolderPath>? get_ignored_paths() {
        return null;
    }
    
    public override bool delete_is_archive() {
        return false;
    }
}

