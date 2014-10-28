/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// LibSecret password adapter.
public class SecretMediator : Geary.CredentialsMediator, Object {
    private const string OLD_GEARY_USERNAME_PREFIX = "org.yorba.geary username:";
    
    private string get_key_name(Geary.Service service, string user) {
        switch (service) {
            case Geary.Service.IMAP:
                return "org.yorba.geary imap_username:" + user;
            
            case Geary.Service.SMTP:
                return "org.yorba.geary smtp_username:" + user;
            
            default:
                assert_not_reached();
        }
    }

    private Geary.Credentials get_credentials(Geary.Service service, Geary.AccountInformation account_information) {
        switch (service) {
            case Geary.Service.IMAP:
                return account_information.imap_credentials;

            case Geary.Service.SMTP:
                return account_information.smtp_credentials;

            default:
                assert_not_reached();
        }
    }

    private async string? migrate_old_password(string old_key, string new_key, Cancellable? cancellable)
        throws Error {
        string? password = yield Secret.password_lookup(Secret.SCHEMA_COMPAT_NETWORK, cancellable,
            "user", old_key);
        if (password != null) {
            bool result = yield Secret.password_store(Secret.SCHEMA_COMPAT_NETWORK,
                null, new_key, password, cancellable, "user", new_key);
            if (result)
                yield Secret.password_clear(Secret.SCHEMA_COMPAT_NETWORK, cancellable, "user", old_key);
        }
        
        return password;
    }
    
    public virtual async string? get_password_async(
        Geary.Service service, Geary.AccountInformation account_information, Cancellable? cancellable = null)
        throws Error {
        string key_name = get_key_name(service, account_information.email);
        string? password = yield Secret.password_lookup(Secret.SCHEMA_COMPAT_NETWORK, cancellable,
            "user", key_name);
        
        // fallback to the old keyring key string for upgrading users
        if (password == null) {
            Geary.Credentials creds = get_credentials(service, account_information);
            
            // <= 0.6
            password = yield migrate_old_password(get_key_name(service, creds.user),
                key_name, cancellable);
            
            // 0.1
            if (password == null) {
                password = yield migrate_old_password(OLD_GEARY_USERNAME_PREFIX + creds.user,
                    key_name, cancellable);
            }
        }
        
        if (password == null)
            debug("Unable to fetch password in libsecret keyring for %s", account_information.email);
        
        return password;
    }
    
    public virtual async void set_password_async(
        Geary.Service service, Geary.AccountInformation account_information,
        Cancellable? cancellable = null) throws Error {
        string key_name = get_key_name(service, account_information.email);
        Geary.Credentials credentials = get_credentials(service, account_information);
        
        bool result = yield Secret.password_store(Secret.SCHEMA_COMPAT_NETWORK,
            null, key_name, credentials.pass, cancellable, "user", key_name);
        if (!result)
            debug("Unable to store password for \"%s\" in libsecret keyring", key_name);
    }
    
    public virtual async void clear_password_async(
        Geary.Service service, Geary.AccountInformation account_information, Cancellable? cancellable = null)
        throws Error {
        // delete new-style and old-style locations
        Geary.Credentials credentials = get_credentials(service, account_information);
        // new-style
        yield Secret.password_clear(Secret.SCHEMA_COMPAT_NETWORK, cancellable, "user",
            get_key_name(service, account_information.email));
        // <= 0.6
        yield Secret.password_clear(Secret.SCHEMA_COMPAT_NETWORK, cancellable, "user",
            get_key_name(service, credentials.user));
        // 0.1
        yield Secret.password_clear(Secret.SCHEMA_COMPAT_NETWORK, cancellable, "user",
            OLD_GEARY_USERNAME_PREFIX + credentials.user);
    }
    
    public virtual async bool prompt_passwords_async(Geary.ServiceFlag services,
        Geary.AccountInformation account_information,
        out string? imap_password, out string? smtp_password,
        out bool imap_remember_password, out bool smtp_remember_password) throws Error {
        // Our dialog doesn't support asking for both at once, even though this
        // API would indicate it does.  We need to revamp the API.
        assert(!services.has_imap() || !services.has_smtp());
        
        // If the main window is hidden, make it visible now and present to user as transient parent
        Gtk.Window? main_window = GearyApplication.instance.controller.main_window;
        if (main_window != null && !main_window.visible) {
            main_window.show_all();
            main_window.present_with_time(Gdk.CURRENT_TIME);
        }
        
        PasswordDialog password_dialog = new PasswordDialog(main_window, services.has_smtp(),
            account_information, services);
        
        if (!password_dialog.run()) {
            imap_password = null;
            smtp_password = null;
            imap_remember_password = false;
            smtp_remember_password = false;
            return false;
        }
        
        // password_dialog.password should never be null at this point. It will only be null when
        // password_dialog.run() returns false, in which case we have already returned.
        if (services.has_smtp()) {
            imap_password = null;
            imap_remember_password = false;
            smtp_password = password_dialog.password;
            smtp_remember_password = password_dialog.remember_password;
        } else {
            imap_password = password_dialog.password;
            imap_remember_password = password_dialog.remember_password;
            smtp_password = null;
            smtp_remember_password = false;
        }
        return true;
    }
}
