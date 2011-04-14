/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Tag : StringParameter {
    public const string UNTAGGED_VALUE = "*";
    
    private static Tag? untagged = null;
    
    public Tag(string value) {
        base (value);
    }
    
    public Tag.from_parameter(StringParameter strparam) {
        base (strparam.value);
    }
    
    public static Tag get_untagged() {
        if (untagged == null)
            untagged = new Tag(UNTAGGED_VALUE);
        
        return untagged;
    }
    
    public bool is_tagged() {
        return value != UNTAGGED_VALUE;
    }
    
    public bool equals(Tag? tag) {
        if (this == tag)
            return true;
        
        if (tag == null)
            return false;
        
        return (this.value == tag.value);
    }
}

