/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Credentials {
    public string user { get; private set; }
    public string pass { get; set; }
    
    public Credentials(string? user, string? pass) {
        this.user = user ?? "";
        this.pass = pass ?? "";
    }
    
    public string to_string() {
        return "%s".printf(user);
    }
}

