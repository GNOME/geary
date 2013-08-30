/* Copyright 2013 Yorba Foundation
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

public class Geary.Imap.SequenceNumber : Geary.MessageData.IntMessageData, Geary.Imap.MessageData,
    Gee.Comparable<SequenceNumber> {
    /**
     * Minimum value of a valid {@link SequenceNumber}.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-2.3.1.2]]
     */
    public int MIN_VALUE = 1;
    
    /**
     * Create a new {@link SequenceNumber}.
     *
     * This does not check if the value is valid, i.e. >= {@link MIN_VALUE}.
     */
    public SequenceNumber(int value) {
        base (value);
    }
    
    /**
     * Converts an array of ints into an array of {@link SequenceNumber}s.
     */
    public static SequenceNumber[] to_list(int[] value_array) {
        SequenceNumber[] list = new SequenceNumber[0];
        foreach (int value in value_array)
            list += new SequenceNumber(value);
        
        return list;
    }
    
    /**
     * Defined as {@link value} >= {@link MIN_VALUE}.
     */
    public bool is_valid() {
        return value >= MIN_VALUE;
    }
    
    /**
     * Returns a new {@link SequenceNumber} that is one higher than this value.
     *
     */
    public SequenceNumber inc() {
        return new SequenceNumber(value + 1);
    }
    
    /**
     * Returns a new {@link SequenceNumber} that is one lower than this value.
     *
     * Returns null if the decremented value is less than {@link MIN_VALUE}.
     */
    public SequenceNumber? dec() {
        return (value > MIN_VALUE) ? new SequenceNumber(value - 1) : null;
    }
    
    /**
     * Returns a new {@link SequenceNumber} that is one lower than this value.
     *
     * Returns a SequenceNumber of MIN_VALUE if the decremented value is less than it.
     */
    public SequenceNumber dec_clamped() {
        return (value > MIN_VALUE) ? new SequenceNumber(value - 1) : new SequenceNumber(MIN_VALUE);
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
        return value - other.value;
    }
    
    public string serialize() {
        return value.to_string();
    }
}

