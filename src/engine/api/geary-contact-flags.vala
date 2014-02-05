/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A collection of NamedFlags that can be used to enable/disable various user-defined
 * options for a contact.  System- or Geary-defined flags are available as static
 * members.
 */

public class Geary.ContactFlags : Geary.NamedFlags {
    private static NamedFlag? _always_load_remote_images = null;
    public static NamedFlag ALWAYS_LOAD_REMOTE_IMAGES { get {
        if (_always_load_remote_images == null)
            _always_load_remote_images = new NamedFlag("ALWAYSLOADREMOTEIMAGES");
        
        return _always_load_remote_images;
    } }
    
    public ContactFlags() {
    }
    
    public static ContactFlags deserialize(string? flags) {
        if (String.is_empty(flags))
            return new ContactFlags();
        
        ContactFlags result = new ContactFlags();
        
        string[] tokens = flags.split(" ");
        foreach (string flag in tokens)
            result.add(new NamedFlag(flag));
        
        return result;
    }
    
    public inline bool always_load_remote_images() {
        return contains(ALWAYS_LOAD_REMOTE_IMAGES);
    }
    
    public string serialize() {
        string ret = "";
        foreach (NamedFlag flag in list)
            ret += flag.serialize() + " ";
        
        return ret.strip();
    }
}

