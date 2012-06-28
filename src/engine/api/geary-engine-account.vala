/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.EngineAccount : Geary.AbstractAccount {
    private AccountInformation account_information;
    
    public virtual signal void email_sent(Geary.RFC822.Message rfc822) {
    }
    
    public EngineAccount(string name, string username, AccountInformation account_information,
        File user_data_dir) {
        base (name);
        
        this.account_information = account_information;
    }
    
    protected virtual void notify_email_sent(Geary.RFC822.Message rfc822) {
        email_sent(rfc822);
    }
    
    public virtual AccountInformation get_account_information() {
        return account_information;
    }
    
    public abstract bool delete_is_archive();
    
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
}
