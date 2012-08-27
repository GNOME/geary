/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine {
    public static File? user_data_dir { get; private set; default = null; }
    public static File? resource_dir { get; private set; default = null; }
    
    private static bool inited = false;
    
    /**
     * Geary.Engine.init() should be the first call any application makes prior to calling into
     * the Geary engine.
     */
    public static void init(File _user_data_dir, File _resource_dir) {
        if (inited)
            return;
        
        user_data_dir = _user_data_dir;
        resource_dir = _resource_dir;
        
        // Initialize GMime
        GMime.init(0);
        
        inited = true;
    }
    
    /**
     * Returns a list of AccountInformation objects representing accounts setup for use by the Geary
     * engine.
     */
    public static Gee.List<AccountInformation> get_accounts() throws Error {
        Gee.ArrayList<AccountInformation> list = new Gee.ArrayList<AccountInformation>();
        
        if (!inited) {
            debug("Geary.Engine.get_accounts(): not initialized");
            
            return list;
        }
        
        FileEnumerator enumerator = user_data_dir.enumerate_children("standard::*", 
            FileQueryInfoFlags.NONE);
        
        FileInfo? info = null;
        while ((info = enumerator.next_file()) != null) {
            if (info.get_file_type() == FileType.DIRECTORY)
                list.add(new AccountInformation(user_data_dir.get_child(info.get_name())));
        }
        
        return list;
    }
    
    /**
     * Returns a Geary.AccountInformation for the specified email address.  If the account
     * has not been set up previously, an object is returned, although it's merely backed by memory
     * and filled with defaults.  Otherwise, the account information for that address is loaded.
     *
     * "email" in this case means the Internet mailbox for the account, i.e. username@domain.com.
     * Use the "address" field of RFC822.MailboxAddress for this parameter.
     */
    public static Geary.AccountInformation get_account_for_email(string email) throws Error {
        return new Geary.AccountInformation(user_data_dir.get_child(email));
    }
}

