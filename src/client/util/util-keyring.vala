/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

const string GEARY_USERNAME_PREFIX = "org.yorba.geary username:";

public static void keyring_save_password(string username, string password) {
    string name = GEARY_USERNAME_PREFIX + username;
    
    GnomeKeyring.Result res = GnomeKeyring.store_password_sync(GnomeKeyring.NETWORK_PASSWORD, null, 
        name, password, "user", name);
    
    assert(res == GnomeKeyring.Result.OK);
}

// Returns the password for the given username, or null if not set.
public static string? keyring_get_password(string username) {
    string password;
    GnomeKeyring.Result res = GnomeKeyring.find_password_sync(GnomeKeyring.NETWORK_PASSWORD, out password, 
        "user", GEARY_USERNAME_PREFIX + username);
    
    return res == GnomeKeyring.Result.OK ? password : null;
}
