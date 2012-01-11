/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine {
    private static bool gmime_inited = false;
    
    public static Geary.EngineAccount open(Geary.Credentials cred, File user_data_dir, 
        File resource_dir) throws Error {
        // Initialize GMime
        if (!gmime_inited) {
            GMime.init(0);
            gmime_inited = true;
        }
        
        // Only Gmail today
        return new GmailAccount(
            "Gmail account %s".printf(cred.to_string()), cred.user, user_data_dir,
            new Geary.Imap.Account(GmailAccount.IMAP_ENDPOINT, GmailAccount.SMTP_ENDPOINT, cred),
            new Geary.Sqlite.Account(cred, user_data_dir, resource_dir));
    }
    
    // Returns a list of usernames associated with Geary.
    public static Gee.List<string> get_usernames(File user_data_dir) throws Error {
        Gee.ArrayList<string> list = new Gee.ArrayList<string>();
        
        FileEnumerator enumerator = user_data_dir.enumerate_children("standard::*", 
            FileQueryInfoFlags.NONE);
        
        FileInfo? info = null;
        while ((info = enumerator.next_file()) != null) {
            if (info.get_file_type() == FileType.DIRECTORY)
                list.add(info.get_name());
        }
        
        return list;
    }
}
