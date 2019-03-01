/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * US-ASCII string utilities.
 *
 * Using ASCII-specific, non-localised functions is essential when
 * dealing with protocol strings since any case-insensitive
 * comparisons may be incorrect under certain locales — especially for
 * Turkish, where translating between upper-case and lower-case `i` is
 * not necessarily preserved.
 */
namespace Geary.Ascii {

public int index_of(string str, char ch) {
    // Use a pointer and explicit null check, since testing against
    // the length of the string as in a traditional for loop will mean
    // a call to strlen(), making the loop O(n^2)
    int ret = -1;
    char *strptr = str;
    int i = 0;
    while (*strptr != String.EOS) {
        if (*strptr++ == ch) {
            ret = i;
            break;
        }
        i++;
    }
    return ret;
}

public int last_index_of(string str, char ch) {
    // Use a pointer and explicit null check, since testing against
    // the length of the string as in a traditional for loop will mean
    // a call to strlen(), making the loop O(n^2)
    int ret = -1;
    char *strptr = str;
    int i = 0;
    while (*strptr != String.EOS) {
        if (*strptr++ == ch) {
            ret = i;
        }
        i++;
    }
    return ret;
}

public bool get_next_char(string str, ref int index, out char ch) {
    ch = str[index++];

    return ch != String.EOS;
}

public inline int strcmp(string a, string b) {
    return GLib.strcmp(a, b);
}

public inline int stricmp(string a, string b) {
    return a.ascii_casecmp(b);
}

public inline bool str_equal(string a, string b) {
    return a == b;
}

public inline bool stri_equal(string a, string b) {
    return a.ascii_casecmp(b) == 0;
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

public inline string strdown(string str) {
    return str.ascii_down();
}

public inline string strup(string str) {
    return str.ascii_up();
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

