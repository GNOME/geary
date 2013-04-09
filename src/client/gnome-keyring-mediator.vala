/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class GnomeKeyringMediator : Geary.CredentialsMediator, Object {
    private const string OLD_GEARY_USERNAME_PREFIX = "org.yorba.geary username:";
    
    private string get_key_name(Geary.CredentialsMediator.Service service, string user) {
        switch (service) {
            case Service.IMAP:
                return "org.yorba.geary imap_username:" + user;
            
            case Service.SMTP:
                return "org.yorba.geary smtp_username:" + user;
            
            default:
                assert_not_reached();
        }
    }
    
    public virtual async string? get_password_async(
        Geary.CredentialsMediator.Service service, string username) throws Error {
        string password;
        GnomeKeyring.Result result = GnomeKeyring.find_password_sync(GnomeKeyring.NETWORK_PASSWORD,
            out password, "user", get_key_name(service, username));
        
        if (result != GnomeKeyring.Result.OK) {
            // fallback to the old keyring key string for upgrading users
            result = GnomeKeyring.find_password_sync(GnomeKeyring.NETWORK_PASSWORD, out password,
                "user", OLD_GEARY_USERNAME_PREFIX + username);
        }
        
        if (result != GnomeKeyring.Result.OK)
            debug("Unable to fetch password in GNOME keyring: %s", result.to_string());
        
        return (result == GnomeKeyring.Result.OK) ? password : null;
    }
    
    public virtual async void set_password_async(
        Geary.CredentialsMediator.Service service, Geary.Credentials credentials) throws Error {
        string key_name = get_key_name(service, credentials.user);
        
        GnomeKeyring.Result result = GnomeKeyring.store_password_sync(GnomeKeyring.NETWORK_PASSWORD,
            null, key_name, credentials.pass, "user", key_name);
        
        if (result != GnomeKeyring.Result.OK)
            debug("Unable to store password in GNOME keyring: %s", result.to_string());
    }
    
    public virtual async void clear_password_async(
        Geary.CredentialsMediator.Service service, string username) throws Error {
        // delete new-style and old-style locations
        GnomeKeyring.delete_password_sync(GnomeKeyring.NETWORK_PASSWORD, "user",
            get_key_name(service, username));
        GnomeKeyring.delete_password_sync(GnomeKeyring.NETWORK_PASSWORD, "user",
            OLD_GEARY_USERNAME_PREFIX + username);
    }
    
    public virtual async bool prompt_passwords_async(Geary.CredentialsMediator.ServiceFlag services,
        Geary.AccountInformation account_information,
        out string? imap_password, out string? smtp_password,
        out bool imap_remember_password, out bool smtp_remember_password) throws Error {
        bool first_try = !account_information.imap_credentials.is_complete() ||
            (account_information.smtp_credentials != null &&
            !account_information.smtp_credentials.is_complete());
        
        PasswordDialog password_dialog = new PasswordDialog(account_information, first_try,
            services);
        
        if (!password_dialog.run()) {
            imap_password = null;
            smtp_password = null;
            imap_remember_password = false;
            smtp_remember_password = false;
            return false;
        }
        
        // password_dialog.password should never be null at this point. It will only be null when
        // password_dialog.run() returns false, in which case we have already returned.
        imap_password = password_dialog.imap_password;
        smtp_password = password_dialog.smtp_password;
        imap_remember_password = password_dialog.remember_password;
        smtp_remember_password = password_dialog.remember_password;
        return true;
    }
}
