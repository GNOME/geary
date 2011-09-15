/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine {
    private static bool gmime_inited = false;
    
    public static Geary.EngineAccount open(Geary.Credentials cred) throws Error {
        // Initialize GMime
        if (!gmime_inited) {
            GMime.init(0);
            gmime_inited = true;
        }
        
        // Only Gmail today
        return new GmailAccount(
            "Gmail account %s".printf(cred.to_string()),
            new Geary.Imap.Account(cred, Imap.ClientConnection.DEFAULT_PORT_TLS),
            new Geary.Sqlite.Account(cred));
    }
    
    // Returns a list of usernames associated with Geary.
    public static Gee.List<string> get_usernames() throws Error {
        Gee.ArrayList<string> list = new Gee.ArrayList<string>();
        
        FileEnumerator enumerator = YorbaApplication.instance.get_user_data_directory().
            enumerate_children("standard::*", FileQueryInfoFlags.NONE);
        
        FileInfo? info = null;
        while ((info = enumerator.next_file()) != null) {
            if (info.get_file_type() == FileType.DIRECTORY)
                list.add(info.get_name());
        }
        
        return list;
    }
}
