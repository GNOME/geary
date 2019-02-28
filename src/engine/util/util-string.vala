/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// GLib's character-based substring function.
[CCode (cname = "g_utf8_substring")]
extern string glib_substring(string str, long start_pos, long end_pos);

namespace Geary.String {

/** The end-of-string character, NUL. */
public const char EOS = '\0';

/** A regex that matches one or more whitespace or non-printing chars. */
public const string WS_OR_NP = "[[:space:][:cntrl:]]+";


public bool is_empty_or_whitespace(string? str) {
    return (str == null || str[0] == EOS || str.strip()[0] == EOS);
}

public inline bool is_empty(string? str) {
    return (str == null || str[0] == EOS);
}

public int count_char(string s, unichar c) {
    int count = 0;
    for (int index = 0; (index = s.index_of_char(c, index)) >= 0; ++index, ++count)
        ;
    return count;
}

public bool contains_any_char(string str, unichar[] chars) {
    int index = 0;
    unichar ch;
    while (str.get_next_char(ref index, out ch)) {
        if (ch in chars)
            return true;
    }

    return false;
}

public uint stri_hash(string str) {
    return str_hash(str.down());
}

public bool stri_equal(string a, string b) {
    return str_equal(a.down(), b.down());
}

public int stri_cmp(string a, string b) {
    return strcmp(a.down(), b.down());
}

/**
 * Removes redundant white space and non-printing characters.
 *
 * @return the input string /str/, modified so that any non-printing
 * characters are converted to spaces, all consecutive spaces are
 * coalesced into a single space, and stripped of leading and trailing
 * white space. If //null// is passed in, the empty string is
 * returned.
 */
public string reduce_whitespace(string? str) {
    string s = str ?? "";
    try {
        s = new Regex(WS_OR_NP).replace(s, -1, 0, " ");
    } catch (Error err) {
        // Oh well
    }
    return s.strip();
}

// Slices a string to, at most, max_length number of bytes (NOT including the null.)
// Due to the nature of UTF-8, it may be a few bytes shorter than the maximum.
//
// If the string is less than max_length bytes, it will be return unchanged.
public string safe_byte_substring(string s, ssize_t max_length) {
    if (s.length < max_length)
        return s;

    return glib_substring(s, 0, s.char_count(max_length));
}

}

