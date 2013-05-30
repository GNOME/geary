/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP command tag.
 *
 * Tags are assigned by the client for each {@link Command} it sends to the server.  Tags have
 * a general form of <a-z><000-999>, although that's only by convention and is not required.
 *
 * Special tags exist, namely to indicated an untagged response and continuations.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.2.1]]
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
    
    internal static void init() {
        get_untagged();
        get_continuation();
        get_unassigned();
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
    
    /**
     * Returns true if the StringParameter resembles a tag token: an unquoted non-empty string
     * that either matches the untagged or continuation special tags or 
     */
    public static bool is_tag(StringParameter stringp) {
        if (stringp is QuotedStringParameter)
            return false;
        
        if (String.is_empty(stringp.value))
            return false;
        
        if (stringp.value == UNTAGGED_VALUE || stringp.value == CONTINUATION_VALUE)
            return true;
        
        int index = 0;
        unichar ch;
        while (stringp.value.get_next_char(ref index, out ch)) {
            if (DataFormat.is_tag_special(ch))
                return false;
        }
        
        return true;
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

