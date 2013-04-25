/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.EmailFlag : BaseObject, Gee.Hashable<Geary.EmailFlag> {
    private string name;
    
    public EmailFlag(string name) {
        this.name = name;
    }
    
    public bool equal_to(Geary.EmailFlag other) {
        if (this == other)
            return true;
        
        return name.down() == other.name.down();
    }
    
    public uint hash() {
        return name.down().hash();
    }
    
    public string to_string() {
        return name;
    }
}

