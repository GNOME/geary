/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.EngineAccount : Geary.AbstractAccount {
    public virtual Geary.AccountSettings settings { get; private set; }
    
    public virtual signal void email_sent(Geary.RFC822.Message rfc822) {
    }
    
    internal EngineAccount(string name, AccountSettings settings) {
        base (name);
        
        this.settings = settings;
    }
    
    protected virtual void notify_email_sent(Geary.RFC822.Message rfc822) {
        email_sent(rfc822);
    }
    
    public abstract async void send_email_async(Geary.ComposedEmail composed, Cancellable? cancellable = null)
        throws Error;
}
