/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Engine {
    private static bool gmime_inited = false;
    public static File? user_data_dir { get; private set; default = null; }
    public static File? resource_dir { get; private set; default = null; }

    public static void init(File _user_data_dir, File _resource_dir) {
        user_data_dir = _user_data_dir;
        resource_dir = _resource_dir;
        
        // Initialize GMime
        if (!gmime_inited) {
            GMime.init(0);
            gmime_inited = true;
        }
    }
    
    // Returns a list of usernames associated with Geary.
    public static Gee.List<string> get_usernames() throws Error {
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
