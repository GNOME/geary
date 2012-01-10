/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Geary.String {

public inline bool is_empty(string? str) {
    return (str == null || str[0] == 0);
}

public int ascii_cmp(string a, string b) {
    return strcmp(a, b);
}

public int ascii_cmpi(string a, string b) {
    char *aptr = a;
    char *bptr = b;
    for (;;) {
        int diff = *aptr - *bptr;
        if (diff != 0)
            return diff;
        
        if (*aptr == '\0')
            return 0;
        
        aptr++;
        bptr++;
    }
}

public inline bool ascii_equal(string a, string b) {
    return ascii_cmp(a, b) == 0;
}

public inline bool ascii_equali(string a, string b) {
    return ascii_cmpi(a, b) == 0;
}

public inline string escape_markup(string? plain) {
    return (!is_empty(plain) && plain.validate()) ? Markup.escape_text(plain) : "";
}

/**
 * Returns char from 0 to 9 converted to an int.  If a non-numeric value, -1 is returned.
 */
public inline int digit_to_int(char ch) {
    return ch.isdigit() ? (ch - '0') : -1;
}

public string uint8_to_hex(uint8[] buffer) {
    StringBuilder builder = new StringBuilder();
    
    foreach (uint8 byte in buffer) {
        if (builder.len > 0)
            builder.append_c(' ');
        
        builder.append("%X (%c)".printf(byte, (char) byte));
    }
    
    return builder.str;
}

// Removes redundant spaces, tabs, and newlines.
public string reduce_whitespace(string _s) {
    string s = _s;
    s = s.replace("\n", " ");
    s = s.replace("\r", " ");
    s = s.replace("\t", " ");
    s = s.strip();
    
    // Condense multiple spaces to one.
    for (int i = 1; i < s.length; i++) {
        if (s.get_char(i) == ' ' && s.get_char(i - 1) == ' ') {
            s = s.slice(0, i - 1) + s.slice(i, s.length);
            i--;
        }
    }
    
    return s;
}

}

