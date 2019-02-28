/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Utility methods for manipulating and examining data particular to MIME.
 */

namespace Geary.Mime.DataFormat {

private const char[] CONTENT_TYPE_TOKEN_SPECIALS = {
    '(', ')', '<', '>', '@', ',', ';', ':', '\\', '"', '/', '[', ']', '?', '='
};

public enum Encoding {
    QUOTING_REQUIRED,
    QUOTING_OPTIONAL,
    UNALLOWED
}

public Encoding get_encoding_requirement(string str) {
    if (String.is_empty(str))
        return Encoding.QUOTING_REQUIRED;

    Encoding encoding = Encoding.QUOTING_OPTIONAL;
    int index = 0;
    for (;;) {
        char ch = str[index++];
        if (ch == String.EOS)
            break;

        if (ch.iscntrl())
            return Encoding.UNALLOWED;

        // don't return immediately, it's possible unallowed characters may still be ahead
        if (ch.isspace() || ch in CONTENT_TYPE_TOKEN_SPECIALS)
            encoding = Encoding.QUOTING_REQUIRED;
    }

    return encoding;
}

}
