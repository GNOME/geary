/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of a numerical {@link Parameter} in an IMAP {@link Command}.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.2]]
 */

public class Geary.Imap.NumberParameter : UnquotedStringParameter {
    public NumberParameter(int num) {
        base (num.to_string());
    }
    
    public NumberParameter.uint(uint num) {
        base (num.to_string());
    }
    
    public NumberParameter.int32(int32 num) {
        base (num.to_string());
    }
    
    public NumberParameter.uint32(uint32 num) {
        base (num.to_string());
    }
    
    public NumberParameter.int64(int64 num) {
        base (num.to_string());
    }
    
    public NumberParameter.uint64(uint64 num) {
        base (num.to_string());
    }
    
    /**
     * Creates a {@link NumberParameter} for a string representation of a number.
     *
     * No checking is performed to verify that the string is only composed of numeric characters.
     * Use {@link is_numeric}.
     */
    public NumberParameter.from_string(string str) {
        base (str);
    }
    
    /**
     * Returns true if the string is composed of numeric characters.
     *
     * The only non-numeric character allowed is a dash ('-') at the beginning of the string to
     * indicate a negative value.  However, note that almost every IMAP use of a number is for a
     * positive value.  is_negative returns set to true if that's the case.  is_negative is only
     * a valid value if the method returns true itself.
     *
     * Empty strings (null or zero-length) are considered non-numeric.  Leading and trailing
     * whitespace are stripped before evaluating the string.
     */
    public static bool is_numeric(string s, out bool is_negative) {
        is_negative = false;
        
        string str = s.strip();
        
        if (String.is_empty(str))
            return false;
        
        bool first_char = true;
        int index = 0;
        for (;;) {
            char ch = str[index++];
            if (ch == String.EOS)
                break;
            
            if (first_char && ch == '-') {
                is_negative = true;
                first_char = false;
                
                continue;
            }
            
            first_char = false;
            
            if (!ch.isdigit())
                return false;
        }
        
        return true;
    }
}

