/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

[DBus (name = "org.yorba.Geary.Conversation", timeout = 120000)]
public class Geary.DBus.Conversation : Object {
    
    public static const string INTERFACE_NAME = "org.yorba.Geary.Conversation";
    
    private Geary.Conversation conversation;
    private Geary.Folder folder;
    
    public Conversation(Geary.Conversation c, Geary.Folder f) {
        conversation = c;
        folder = f;
    }
    
    public async ObjectPath[] get_emails() throws IOError {
        Gee.SortedSet<Geary.Email>? pool = conversation.get_pool_sorted(compare_email);
        if (pool == null)
            return new ObjectPath[0];
        
        ObjectPath[] paths = new ObjectPath[0];
        
        foreach (Geary.Email e in pool) {
            paths += new ObjectPath(Database.instance.get_email_path(e, folder));
        }
        
        return paths;
    }
    
    private static int compare_email(Geary.Email aenvelope, Geary.Email benvelope) {
        int diff = aenvelope.date.value.compare(benvelope.date.value);
    
        // stabilize sort by using the mail's ordering, which is always unique in a folder
        return (diff != 0) ? diff : aenvelope.id.compare(benvelope.id);
    }
    
}
