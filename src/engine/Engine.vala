/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine : Object {
    public static async Account? login(string server, string user, string pass) throws Error {
        Imap.ClientSession account = new Imap.ClientSession(server, Imap.ClientConnection.DEFAULT_PORT_TLS);
        yield account.connect_async();
        yield account.login_async(user, pass);
        
        return account;
    }
}

