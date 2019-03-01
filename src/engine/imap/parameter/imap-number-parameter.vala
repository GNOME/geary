/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of a numerical {@link Parameter} in an IMAP {@link Command} or
 * {@link ServerResponse}.
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
     * Use {@link is_ascii_numeric}.
     */
    public NumberParameter.from_ascii(string ascii) {
        base (ascii);
    }

    /**
     * Returns true if the string is composed of numeric 7-bit characters.
     *
     * The only non-numeric character allowed is a dash ('-') at the beginning of the string to
     * indicate a negative value.  However, note that almost every IMAP use of a number is for a
     * positive value.  is_negative returns set to true if that's the case.  is_negative is only
     * a valid value if the method returns true itself.
     *
     * is_negative is false for zero ("0") and negative zero ("-0").
     *
     * Empty strings (null or zero-length) are considered non-numeric.  Leading and trailing
     * whitespace are stripped before evaluating the string.
     */
    public static bool is_ascii_numeric(string ascii, out bool is_negative) {
        is_negative = false;

        string str = ascii.strip();

        if (String.is_empty(str))
            return false;

        bool has_nonzero = false;
        int index = 0;
        for (;;) {
            char ch = str[index++];
            if (ch == String.EOS)
                break;

            if (index == 1 && ch == '-') {
                is_negative = true;

                continue;
            }

            if (!ch.isdigit())
                return false;

            if (ch != '0')
                has_nonzero = true;
        }

        // watch for negative but no numeric portion
        if (is_negative && str.length == 1)
            return false;

        // no such thing as negative zero
        if (is_negative && !has_nonzero)
            is_negative = false;

        return true;
    }
}

