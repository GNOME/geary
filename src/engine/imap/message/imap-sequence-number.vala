/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of IMAP's sequence number, i.e. 1-based positional addressing within a mailbox.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.3.1.2]]
 *
 * @see UID
 */

public class Geary.Imap.SequenceNumber : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData,
    Gee.Comparable<SequenceNumber> {
    /**
     * Minimum value of a valid {@link SequenceNumber}.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-2.3.1.2]]
     */
    public const int64 MIN = 1;

    /**
     * Upper limit of a valid {@link SequenceNumber}.
     */
    public const int64 MAX = 0xFFFFFFFF;

    /**
     * Create a new {@link SequenceNumber}.
     *
     * This does not check if the value is valid.
     *
     * @see is_value_valid
     * @see SequenceNumber.SequenceNumber.checked
     */
    public SequenceNumber(int64 value) {
        base (value);
    }

    /**
     * Create a new {@link SequenceNumber}, throwing {@link ImapError.INVALID} if an invalid value
     * is passed in.
     *
     * @see is_value_valid
     * @see SequenceNumber
     */
    public SequenceNumber.checked(int64 value) throws ImapError {
        if (!is_value_valid(value))
            throw new ImapError.INVALID("Invalid sequence number %s", value.to_string());

        base (value);
    }

    /**
     * Defined as {@link MessageData.Int64MessageData.value} >= {@link MIN} and <= {@link MAX}.
     */
    public static bool is_value_valid(int64 value) {
        return value >= MIN && value <= MAX;
    }

    /**
     * Defined as {@link MessageData.Int64MessageData.value} >= {@link MIN} and <= {@link MAX}.
     */
    public bool is_valid() {
        return is_value_valid(value);
    }

    /**
     * Returns a new {@link SequenceNumber} that is one lower than this value.
     *
     * Returns null if the decremented value is less than {@link MIN}.
     */
    public SequenceNumber? dec() {
        return (value > MIN) ? new SequenceNumber(value - 1) : null;
    }

    /**
     * Returns a new {@link SequenceNumber} that is one lower than this value.
     *
     * Returns a SequenceNumber of MIN if the decremented value is less than it.
     */
    public SequenceNumber dec_clamped() {
        return (value > MIN) ? new SequenceNumber(value - 1) : new SequenceNumber(MIN);
    }

    /**
     * Returns the {@link SequenceNumber} after the suppled SequenceNumber has been removed from
     * the vector of messages.
     *
     * When a message is removed, positions above it will shift downward while positions below
     * it remain unchanged.  If the position removed matches this SequenceNumber, null is returned.
     */
    public SequenceNumber? shift_for_removed(SequenceNumber removed) {
        int comparison = compare_to(removed);
        if (comparison > 0) {
            // appended message's position is higher than removed message's, so appended's position
            // shifts downward ... dec() returns null if dropping below 1, which is suitable here
            return dec();
        }

        if (comparison == 0) {
            // the appended message was removed outright, so drop from new list
            return null;
        }

        // otherwise, removed position was higher than appended message's, so it doesn't
        // shift
        return this;
    }

    public virtual int compare_to(SequenceNumber other) {
        return (int) (value - other.value).clamp(-1, 1);
    }

    public string serialize() {
        return value.to_string();
    }
}

