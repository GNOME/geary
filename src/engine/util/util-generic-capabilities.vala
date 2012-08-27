/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.GenericCapabilities : Object {
    public string separator { get; private set; }
    
    private Gee.HashMultiMap<string, string?> map = new Gee.HashMultiMap<string, string?>(
        String.stri_hash, String.stri_equal, String.nullable_stri_hash, String.nullable_stri_equal);
    
    /**
     * Creates an empty set of capabilities.
     */
    public GenericCapabilities(string separator) {
        assert(!String.is_empty(separator));
        
        this.separator = separator;
    }
    
    public bool is_empty() {
        return (map.size == 0);
    }
    
    public bool parse_and_add_capability(string text) {
        string[] tokens = text.split(separator, 2);
        if (tokens.length == 1)
            add_capability(tokens[0]);
        else if (tokens.length == 2)
            add_capability(tokens[0], tokens[1]);
        else
            return false;
        
        return true;
    }
    
    public void add_capability(string name, string? setting = null) {
        map.set(name, String.is_empty(setting) ? null : setting);
    }
    
    /**
     * Returns true only if the capability was named as available by the server.
     */
    public bool has_capability(string name) {
        return map.contains(name);
    }
    
    /**
     * Returns true only if the capability and the associated setting were both named as available
     * by the server.
     */
    public bool has_setting(string name, string? setting) {
        if (!map.contains(name))
            return false;
        
        if (String.is_empty(setting))
            return true;
        
        return map.get(name).contains(setting);
    }
    
    /**
     * Returns null if either the capability is available but has no associated settings, or if the
     * capability is not available.  Thus, use has_capability() to determine if available, then
     * this method to get its value (if one is expected).  Often has_setting() is a better choice.
     */
    public Gee.Collection<string>? get_settings(string name) {
        Gee.Collection<string> settings = map.get(name);
        
        return (settings.size > 0) ? settings : null;
    }
    
    public Gee.Set<string>? get_all_names() {
        Gee.Set<string> names = map.get_keys();
        
        return (names.size > 0) ? names : null;
    }
    
    private void append(StringBuilder builder, string text) {
        if (!String.is_empty(builder.str))
            builder.append_c(' ');
        
        builder.append(text);
    }
    
    public virtual string to_string() {
        Gee.Set<string>? names = get_all_names();
        if (names == null || names.size == 0)
            return "";
        
        StringBuilder builder = new StringBuilder();
        foreach (string name in names) {
            Gee.Collection<string>? settings = get_settings(name);
            if (settings == null || settings.size == 0) {
                append(builder, name);
            } else {
                foreach (string setting in settings) {
                    if (String.is_empty(setting))
                        append(builder, name);
                    else
                        append(builder, "%s%s%s".printf(name, separator, setting));
                }
            }
        }
        
        return builder.str;
    }
}

