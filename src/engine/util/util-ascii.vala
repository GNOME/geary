/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Ascii {

public bool get_next_char(string str, ref int index, out char ch) {
    ch = str[index++];

    return ch != String.EOS;
}

public bool stri_equal(string a, string b) {
    // XXX Is this marginally faster than a.down() == b.down() in the
    // best case, slower in the worse case, so not worth it?
    char *aptr = a;
    char *bptr = b;
    for (;;) {
        int diff = (int) (*aptr).tolower() - (int) (*bptr).tolower();
        if (diff != 0)
            return false;

        if (*aptr == String.EOS)
            return true;

        aptr++;
        bptr++;
    }
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

