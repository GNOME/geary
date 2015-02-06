/* Copyright 2014-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// These calls are bound to the string class in Vala 0.26.  When that version of Vala is the
// minimum, these can be dropped and Ascii.strup and Ascii.strdown can use the string methods.
extern string g_ascii_strup(string str, ssize_t len = -1);
extern string g_ascii_strdown(string str, ssize_t len = -1);

namespace Geary.Ascii {

public int index_of(string str, char ch) {
    char *strptr = str;
    int index = 0;
    for (;;) {
        char strch = *strptr++;
        
        if (strch == String.EOS)
            return -1;
        
        if (strch == ch)
            return index;
        
        index++;
    }
}

public bool get_next_char(string str, ref int index, out char ch) {
    ch = str[index++];
    
    return ch != String.EOS;
}

public inline int strcmp(string a, string b) {
    return GLib.strcmp(a, b);
}

public int stricmp(string a, string b) {
    char *aptr = a;
    char *bptr = b;
    for (;;) {
        int diff = (int) (*aptr).tolower() - (int) (*bptr).tolower();
        if (diff != 0)
            return diff;
        
        if (*aptr == String.EOS)
            return 0;
        
        aptr++;
        bptr++;
    }
}

public inline bool str_equal(string a, string b) {
    return a == b;
}

public inline bool stri_equal(string a, string b) {
    return stricmp(a, b) == 0;
}

public bool nullable_stri_equal(string? a, string? b) {
    if (a == null)
        return (b == null);
    
    // a != null, so always false
    if (b == null)
        return false;
    
    return stri_equal(a, b);
}

public uint str_hash(string str) {
    return Collection.hash_memory_stream((char *) str, String.EOS, null);
}

public uint stri_hash(string str) {
    return Collection.hash_memory_stream((char *) str, String.EOS, (b) => {
        return ((char) b).tolower();
    });
}

public uint nullable_stri_hash(string? str) {
    return (str != null) ? stri_hash(str) : 0;
}

public string strdown(string str) {
    return g_ascii_strdown(str);
}

public string strup(string str) {
    return g_ascii_strup(str);
}

/**
 * Returns true if the ASCII string contains only whitespace and at least one numeric character.
 */
public bool is_numeric(string str) {
    bool numeric_found = false;
    char *strptr = str;
    for (;;) {
        char ch = *strptr++;
        
        if (ch == String.EOS)
            break;
        
        if (ch.isdigit())
            numeric_found = true;
        else if (!ch.isspace())
            return false;
    }
    
    return numeric_found;
}

/**
 * Returns char from 0 to 9 converted to an int.  If a non-numeric value, -1 is returned.
 */
public inline int digit_to_int(char ch) {
    return ch.isdigit() ? (ch - '0') : -1;
}

}

