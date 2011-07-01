/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine {
    public static Geary.EngineAccount open(Geary.Credentials cred) throws Error {
        // Only Gmail today
        return new GenericImapAccount(
            "Gmail account %s".printf(cred.to_string()),
            new Geary.Imap.Account(cred, Imap.ClientConnection.DEFAULT_PORT_TLS),
            new Geary.Sqlite.Account(cred));
    }
}
