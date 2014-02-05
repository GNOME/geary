/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Imap.DataFormat {

private const char[] ATOM_SPECIALS = {
    '(', ')', '{', ' ', '%', '*', '"'
};

private const char[] TAG_SPECIALS = {
    '(', ')', '{', '%', '\"', '\\', '+'
};

public enum Quoting {
    REQUIRED,
    OPTIONAL,
    UNALLOWED
}

private bool is_special_char(char ch, char[] ar, string? exceptions) {
    if (ch > 0x7F || ch.iscntrl())
        return true;
    
    if (ch in ar)
        return (exceptions != null) ? exceptions.index_of_char(ch) < 0 : true;
    
    return false;
}

/**
 * Returns true if the character is considered an atom special.  Note that while documentation
 * indicates that the backslash cannot be used in an atom, they *are* used for message flags and
 * thus must be special cased by the caller.
 */
public inline bool is_atom_special(char ch, string? exceptions = null) {
    return is_special_char(ch, ATOM_SPECIALS, exceptions);
}

/**
 * Tag specials are like atom specials but include the continuation character ('+').  Also, the
 * star character is allowed, although technically only correct in the context of a status response;
 * it's the responsibility of the caller to catch this.
 */
public bool is_tag_special(char ch, string? exceptions = null) {
    return is_special_char(ch, TAG_SPECIALS, exceptions);
}

/**
 * Returns Quoting to indicate if the string must be quoted before sent on the wire, of if it
 * must be sent as a literal.
 */
public Quoting is_quoting_required(string str) {
    if (String.is_empty(str))
        return Quoting.REQUIRED;
    
    int index = 0;
    for (;;) {
        char ch = str[index++];
        if (ch == String.EOS)
            break;
        
        if (ch > 0x7F)
            return Quoting.UNALLOWED;
        
        switch (ch) {
            case '\n':
            case '\r':
                return Quoting.UNALLOWED;
            
            default:
                if (is_atom_special(ch))
                    return Quoting.REQUIRED;
            break;
        }
    }
    
    return Quoting.OPTIONAL;
}

/**
 * Converts the supplied string to a quoted string and returns whether or not the quoted format
 * is required on the wire.  If Quoting.UNALLOWED is returned, the only way to represent the string
 * is with a literal.
 */
public Quoting convert_to_quoted(string str, out string quoted) {
    Quoting requirement = String.is_empty(str) ? Quoting.REQUIRED : Quoting.OPTIONAL;
    quoted = "";
    
    StringBuilder builder = new StringBuilder("\"");
    int index = 0;
    for (;;) {
        char ch = str[index++];
        if (ch == String.EOS)
            break;
        
        if (ch > 0x7F)
            return Quoting.UNALLOWED;
        
        switch (ch) {
            case '\n':
            case '\r':
                return Quoting.UNALLOWED;
            
            case '"':
            case '\\':
                requirement = Quoting.REQUIRED;
                builder.append_c('\\');
                builder.append_c(ch);
            break;
            
            default:
                if (is_atom_special(ch))
                    requirement = Quoting.REQUIRED;
                
                builder.append_c(ch);
            break;
        }
    }
    
    quoted = builder.append_c('"').str;
    
    return requirement;
}

}

