/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

const string GEARY_USERNAME_PREFIX = "org.yorba.geary username:";

public static bool keyring_save_password(Geary.Credentials credentials) {
    string name = GEARY_USERNAME_PREFIX + credentials.user;
    
    GnomeKeyring.Result result = GnomeKeyring.store_password_sync(GnomeKeyring.NETWORK_PASSWORD,
        null, name, credentials.pass, "user", name);
    
    return result == GnomeKeyring.Result.OK;
}

public static void keyring_delete_password(string username) {
    GnomeKeyring.delete_password_sync(GnomeKeyring.NETWORK_PASSWORD, "user",
        GEARY_USERNAME_PREFIX + username);
}

// Returns the password for the given username, or null if not set.
public static string? keyring_get_password(string username) {
    string password;
    GnomeKeyring.Result res = GnomeKeyring.find_password_sync(GnomeKeyring.NETWORK_PASSWORD,
        out password, "user", GEARY_USERNAME_PREFIX + username);
    
    return res == GnomeKeyring.Result.OK ? password : null;
}
