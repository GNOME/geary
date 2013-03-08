/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailFlag : BaseObject, Geary.Equalable, Geary.Hashable {
    private string name;
    
    public EmailFlag(string name) {
        this.name = name;
    }
    
    public bool equals(Equalable o) {
        EmailFlag? other = o as EmailFlag;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return name.down() == other.name.down();
    }
    
    public uint to_hash() {
        return name.down().hash();
    }
    
    public string to_string() {
        return name;
    }
}

