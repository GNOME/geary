/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

const string OLD_GEARY_USERNAME_PREFIX = "org.yorba.geary username:";

public enum PasswordType {
    IMAP,
    SMTP;
    
    public string get_prefix() {
        switch (this) {
            case IMAP:
                return "org.yorba.geary imap_username:";
            
            case SMTP:
                return "org.yorba.geary smtp_username:";
            
            default:
                assert_not_reached();
        }
    }
}

[Flags]
public enum PasswordTypeFlag {
    IMAP,
    SMTP;
    
    public bool has_imap() {
        return (this & IMAP) == IMAP;
    }
    
    public bool has_smtp() {
        return (this & SMTP) == SMTP;
    }
}

private static string keyring_get_key(PasswordType password_type, string username) {
    return password_type.get_prefix() + username;
}

public static bool keyring_save_password(Geary.Credentials credentials, PasswordType password_type) {
    string key = keyring_get_key(password_type, credentials.user);
    
    GnomeKeyring.Result result = GnomeKeyring.store_password_sync(GnomeKeyring.NETWORK_PASSWORD,
        null, key, credentials.pass, "user", key);
    
    if (result != GnomeKeyring.Result.OK)
        debug("Unable to store password in GNOME keyring: %s", result.to_string());
    
    return (result == GnomeKeyring.Result.OK);
}

public bool keyring_clear_password(string username, PasswordType password_type) {
    string key = keyring_get_key(password_type, username);
    
    GnomeKeyring.Result result = GnomeKeyring.store_password_sync(GnomeKeyring.NETWORK_PASSWORD,
        null, key, "", "user", key);
    
    if (result != GnomeKeyring.Result.OK)
        debug("Unable to clear password in GNOME keyring: %s", result.to_string());
    
    return (result == GnomeKeyring.Result.OK);
}

public static void keyring_delete_password(string username, PasswordType password_type) {
    // delete new-style and old-style locations
    GnomeKeyring.delete_password_sync(GnomeKeyring.NETWORK_PASSWORD, "user",
        keyring_get_key(password_type, username));
    GnomeKeyring.delete_password_sync(GnomeKeyring.NETWORK_PASSWORD, "user",
        OLD_GEARY_USERNAME_PREFIX + username);
}

// Returns the password for the given username, or null if not set.
public static string? keyring_get_password(string username, PasswordType password_type) {
    string password;
    GnomeKeyring.Result result = GnomeKeyring.find_password_sync(GnomeKeyring.NETWORK_PASSWORD,
        out password, "user", keyring_get_key(password_type, username));
    
    if (result != GnomeKeyring.Result.OK) {
        // fallback to the old keyring key string for upgrading users
        result = GnomeKeyring.find_password_sync(GnomeKeyring.NETWORK_PASSWORD, out password,
            "user", OLD_GEARY_USERNAME_PREFIX + username);
    }
    
    if (result != GnomeKeyring.Result.OK)
        debug("Unable to fetch password in GNOME keyring: %s", result.to_string());
    
    return (result == GnomeKeyring.Result.OK) ? password : null;
}

