/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Tag : StringParameter, Hashable, Equalable {
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
    
    public uint to_hash() {
        return str_hash(value);
    }
    
    public bool equals(Equalable e) {
        Tag? tag = e as Tag;
        if (tag == null)
            return false;
        
        if (this == tag)
            return true;
        
        return equals_cs(tag.value);
    }
}

