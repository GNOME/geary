/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Credentials represent a username and a password authenticating a user for access to a resource.
 * More sophisticated schemes exist; this suffices for now.
 *
 * Either property (user, pass) may be null.  This indicates the Credentials are incomplete and
 * need further information (i.e. prompt user for username, fetch password from keyring, etc.)
 * Either field may be a non-null zero-length string; this is considered valid and is_complete()
 * will return true in this case.
 *
 * Note that Geary will hold Credentials in memory for the long-term, usually the duration of the
 * application.  This is because network resources often have to be connected (or reconnected) to
 * in the background and asking the user to reauthenticate each time is deemed inconvenient.
 */

public class Geary.Credentials : BaseObject, Gee.Hashable<Geary.Credentials> {
    public string? user { get; set; }
    public string? pass { get; set; }
    
    public Credentials(string? user, string? pass) {
        this.user = user;
        this.pass = pass;
    }
    
    public bool is_complete() {
        return (user != null) && (pass != null);
    }
    
    public Credentials copy() {
        return new Credentials(user, pass);
    }
    
    public string to_string() {
        return user;
    }
    
    public bool equal_to(Geary.Credentials c) {
        if (this == c)
            return true;
        
        return user == c.user && pass == c.pass;
    }
    
    public uint hash() {
        return "%s%s".printf(user ?? "", pass ?? "").hash();
    }
}

