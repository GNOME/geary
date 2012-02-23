/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.EngineAccount : Geary.AbstractAccount, Geary.Personality {
    private AccountInformation account_information;
    
    public EngineAccount(string name, string username, AccountInformation account_information,
        File user_data_dir) {
        base (name);
        
        this.account_information = account_information;
        account_information.store_async.begin();
    }
    
    public virtual AccountInformation get_account_information() {
        return account_information;
    }
    
    public abstract string get_user_folders_label();
    
    public abstract Geary.SpecialFolderMap? get_special_folder_map();
    
    public abstract Gee.Set<Geary.FolderPath>? get_ignored_paths();
    
    public abstract bool delete_is_archive();
    
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
}

