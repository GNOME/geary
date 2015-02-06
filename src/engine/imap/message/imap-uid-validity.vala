/* Copyright 2013-2015 Yorba Foundation
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
     */
    public const int64 MIN = 1;
    
    /**
     * Maximum valid value for a {@link UIDValidity}.
     */
    public const int64 MAX = 0xFFFFFFFF;
    
    /**
     * Invalid (placeholder) {@link UIDValidity} value.
     */
    public const int64 INVALID = -1;
    
    /**
     * Creates a new {@link UIDValidity} without checking for valid values.
     *
     * @see UIDValidity.checked
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

