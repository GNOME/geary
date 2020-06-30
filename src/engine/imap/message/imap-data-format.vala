/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Micahel Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * IMAP protocol utility functions.
 */
namespace Geary.Imap.DataFormat {

    // RFC 3501 §9:
    //
    // atom-specials   = "(" / ")" / "{" / SP / CTL / list-wildcards /
    //                   quoted-specials / resp-specials
    private const char[] ATOM_SPECIALS = {
        '(', ')', '{', ' ', // CTL chars are handled by is_special_char
        '%', '*',           // list-wildcards
        '"', '\\',          // quoted-specials
        ']'                 // resp-specials
    };

    // RFC 3501 §9:
    //
    // tag             = 1*<any ASTRING-CHAR except "+">
    // ASTRING-CHAR    = ATOM-CHAR / resp-specials
    // ATOM-CHAR       = <any CHAR except atom-specials>
    private const char[] TAG_SPECIALS = {
        '(', ')', '{', ' ', // CTL chars are handled by is_special_char
        '%', '*',           // list-wildcards
        '"', '\\',          // quoted-specials
        '+'                 // tag special
    };

    public enum Quoting {
        REQUIRED,
        OPTIONAL,
        UNALLOWED
    }

    /**
     * Returns true if the character is considered an atom-special.
     *
     * Note that while documentation indicates that the backslash
     * cannot be used in an atom, they *are* used for message flags
     * and thus must be special cased by the caller.
     */
    public bool is_atom_special(char ch, string? exceptions = null) {
        return is_special_char(ch, ATOM_SPECIALS, exceptions);
    }

    /**
     * Returns true if the character is considered a tag-special.
     *
     * Tag specials are like atom specials but include the
     * continuation character ('+'). Also, the star character is
     * allowed, although technically only correct in the context of a
     * status response; it's the responsibility of the caller to catch
     * this.
     */
    public bool is_tag_special(char ch, string? exceptions = null) {
        return is_special_char(ch, TAG_SPECIALS, exceptions);
    }

    /**
     * Determines quoting policy for a string to be sent over the wire.
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

    private inline bool is_special_char(char ch, char[] ar, string? exceptions) {
        // Check for CTL chars
        if (ch <= 0x1F || ch >= 0x7F) {
            return true;
        }

        if (ch in ar) {
            return (exceptions != null) ? Ascii.index_of(exceptions, ch) < 0 : true;
        }

        return false;
    }

}
