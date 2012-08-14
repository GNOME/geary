/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.GenericCapabilities : Object {
    private Gee.ArrayList<string> list = new Gee.ArrayList<string>(String.stri_equal);
    private Gee.HashMap<string, string?> map = new Gee.HashMap<string, string?>(
        String.stri_hash, String.stri_equal);
    
    /**
     * Creates an empty set of capabilities.
     */
    public GenericCapabilities(){
    }
    
    public bool is_empty() {
        return map.is_empty;
    }
    
    public void add_capability(string name, string? setting = null) {
        list.add(name);
        map.set(name, String.is_empty(setting) ? null : setting);
    }
    
    /**
     * Returns true only if the capability was named as available by the server.
     */
    public bool has_capability(string name) {
        return map.has_key(name);
    }
    
    /**
     * Returns true only if the capability and the associated setting were both named as available
     * by the server.
     */
    public bool has_setting(string name, string? setting) {
        if (!map.has_key(name)) {
            return false;
        } else if (String.is_empty(setting)) {
            return true;
        } else {
            string? stored_setting = map.get(name);
            return !String.is_empty(stored_setting) && String.stri_equal(stored_setting, setting);
        }
    }
    
    /**
     * Returns null if either the capability is available but has no associated setting, or if the
     * capability is not available.  Thus, use has_capability() to determine if available, then
     * this method to get its value (if one is expected).  Often has_setting() is a better choice.
     */
    public string? get_setting(string name) {
        return map.get(name);
    }
    
    public Gee.List<string> get_all_names() {
        return list.read_only_view;
    }
    
    public virtual string to_string() {
        StringBuilder builder = new StringBuilder();
        foreach (string name in list) {
            if (!String.is_empty(builder.str))
                builder.append_c(' ');
            
            string? setting = map.get(name);
            if (String.is_empty(setting))
                builder.append(name);
            else
                builder.append_printf("%s=%s", name, setting);
        }
        
        return builder.str;
    }
}

