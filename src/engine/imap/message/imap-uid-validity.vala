/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/*
 * A representation of IMAP's UIDVALIDITY.
 *
 * See [[tools.ietf.org/html/rfc3501#section-2.3.1.1]]
 *
 * @see UID
 */

public class Geary.Imap.UIDValidity : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData {
    /**
     * Minimum valid value for a {@link UIDValidity}.
     *
     * This is smaller than the non-zero minimum RFC 3501 specifies, since at
     * least one mail server has been observed to return zero values. See Issue
     * #1183.
     */
    public const int64 MIN = 0;

    /**
     * Maximum valid value for a {@link UIDValidity}.
     *
     * This is currently larger than what the spec allows for, since
     * at least one mail server was returning values greater than an
     * unsigned 32-bit integer. See Bug 755424.
     */
    public const int64 MAX = 0xFFFFFFFFFFFFFFF;

    /**
     * Invalid (placeholder) {@link UIDValidity} value.
     */
    public const int64 INVALID = -1;

    /**
     * Creates a new {@link UIDValidity} without checking for valid values.
     *
     * @see UIDValidity.UIDValidity.checked
     */
    public UIDValidity(int64 value) {
        base (value);
    }

    /**
     * Creates a new {@link UIDValidity}, throwing {@link ImapError.INVALID} if the supplied value
     * is invalid.
     *
     * @see is_value_valid
     */
    public UIDValidity.checked(int64 value) throws ImapError {
        if (!is_value_valid(value))
            throw new ImapError.INVALID("Invalid UIDVALIDITY %s", value.to_string());

        base (value);
    }

    /**
     * @see is_value_valid
     */
    public bool is_valid() {
        return is_value_valid(value);
    }

    /**
     * Returns true if the supplied value is between {@link MIN} and {@link MAX}, inclusive.
     */
    public static bool is_value_valid(int64 val) {
        return Numeric.int64_in_range_inclusive(val, MIN, MAX);
    }
}

