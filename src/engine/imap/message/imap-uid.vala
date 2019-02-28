/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An IMAP UID.
 *
 * See [[tools.ietf.org/html/rfc3501#section-2.3.1.1]]
 *
 * @see SequenceNumber
 */

public class Geary.Imap.UID : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData,
    Gee.Comparable<Geary.Imap.UID> {
    /**
     * Minimum valid value for a {@link UID}.
     */
    public const int64 MIN = 1;

    /**
     * Maximum valid value for a {@link UID}.
     */
    public const int64 MAX = 0xFFFFFFFF;

    /**
     * Invalid (placeholder) {@link UID} value.
     */
    public const int64 INVALID = -1;

    /**
     * Creates a new {@link UID} without checking for validity.
     *
     * @see UID.UID.checked
     * @see is_value_valid
     */
    public UID(int64 value) {
        base (value);
    }

    /**
     * Creates a new {@link UID}, throwing an {@link ImapError.INVALID} if the supplied value is
     * not a positive unsigned 32-bit integer.
     *
     * @see is_value_valid
     */
    public UID.checked(int64 value) throws ImapError {
        if (!is_value_valid(value))
            throw new ImapError.INVALID("Invalid UID %s", value.to_string());

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

    /**
     * Returns the UID logically next (or after) this one.
     *
     * If clamped this always returns a valid UID, which means returning MIN or MAX if
     * the value is out of range (either direction) or MAX if this value is already MAX.
     *
     * Otherwise, it may return an invalid UID and should be verified before using.
     *
     * @see previous
     * @see is_valid
     */
    public UID next(bool clamped) {
        return clamped ? new UID((value + 1).clamp(MIN, MAX)) : new UID(value + 1);
    }

    /**
     * Returns the UID logically previous (or before) this one.
     *
     * If clamped this always returns a valid UID, which means returning MIN or MAX if
     * the value is out of range (either direction) or MIN if this value is already MIN.
     *
     * Otherwise, it may return a UID where {@link is_valid} returns false.
     *
     * @see next
     * @see is_valid
     */
    public UID previous(bool clamped) {
        return clamped ? new UID((value - 1).clamp(MIN, MAX)) : new UID(value - 1);
    }

    public virtual int compare_to(Geary.Imap.UID other) {
        return (int) (value - other.value).clamp(-1, 1);
    }

    public string serialize() {
        return value.to_string();
    }
}

