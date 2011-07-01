/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Credentials {
    public string server { get; private set; }
    public string user { get; private set; }
    public string pass { get; private set; }
    
    public Credentials(string server, string user, string pass) {
        this.server = server;
        this.user = user;
        this.pass = pass;
    }
    
    public string to_string() {
        return "%s/%s".printf(user, server);
    }
}
