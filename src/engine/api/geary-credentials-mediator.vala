/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public interface Geary.CredentialsMediator : Object {
    public enum Service {
        IMAP,
        SMTP;
    }
    
    [Flags]
    public enum ServiceFlag {
        IMAP,
        SMTP;
        
        public bool has_imap() {
            return (this & IMAP) == IMAP;
        }
        
        public bool has_smtp() {
            return (this & SMTP) == SMTP;
        }
    }
    
    /**
     * Query the key store for the password of the given username for the given
     * service.  Return null if the password wasn't in the key store, or the
     * password if it was.
     */
    public abstract async string? get_password_async(Service service, string username,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Add or update the key store's password entry for the given credentials
     * for the given service.
     */
    public abstract async void set_password_async(Service service,
        Geary.Credentials credentials, Cancellable? cancellable = null) throws Error;
    
    /**
     * Deletes the key store's password entry for the given credentials for the
     * given service.  Do nothing (and do *not* throw an error) if the
     * credentials weren't in the key store.
     */
    public abstract async void clear_password_async(Service service, string username,
        Cancellable? cancellable = null) throws Error;
    
    /**
     * Prompt the user to enter passwords for the given services in the given
     * account.  Set the out parameters for the services to the values entered
     * by the user (out parameters for services not being prompted for are
     * ignored).  Return false if the user tried to cancel the interaction, or
     * true if they tried to proceed.
     */
    public abstract async bool prompt_passwords_async(ServiceFlag services,
        AccountInformation account_information,
        out string? imap_password, out string? smtp_password,
        out bool imap_remember_password, out bool smtp_remember_password) throws Error;
}
