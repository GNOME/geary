/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.Tag : StringParameter, Gee.Hashable<Geary.Imap.Tag> {
    public const string UNTAGGED_VALUE = "*";
    public const string CONTINUATION_VALUE = "+";
    public const string UNASSIGNED_VALUE = "----";
    
    private static Tag? untagged = null;
    private static Tag? unassigned = null;
    private static Tag? continuation = null;
    
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
    
    public static Tag get_continuation() {
        if (continuation == null)
            continuation = new Tag(CONTINUATION_VALUE);
        
        return continuation;
    }
    
    public static Tag get_unassigned() {
        if (unassigned == null)
            unassigned = new Tag(UNASSIGNED_VALUE);
        
        return unassigned;
    }
    
    public bool is_tagged() {
        return (value != UNTAGGED_VALUE) && (value != CONTINUATION_VALUE);
    }
    
    public bool is_continuation() {
        return value == CONTINUATION_VALUE;
    }
    
    public bool is_assigned() {
        return (value != UNASSIGNED_VALUE) && (value != CONTINUATION_VALUE);
    }
    
    public uint hash() {
        return str_hash(value);
    }
    
    public bool equal_to(Geary.Imap.Tag tag) {
        if (this == tag)
            return true;
        
        return equals_cs(tag.value);
    }
}

