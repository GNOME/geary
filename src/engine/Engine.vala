/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine : Object {
    public static async Account? login(string server, string user, string pass) throws Error {
        return new Imap.ClientSessionManager(server, Imap.ClientConnection.DEFAULT_PORT_TLS, user,
            pass);
    }
}

