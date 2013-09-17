/* Copyright 2013 Yorba Foundation
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
    // Using statics because int32.MAX is static, not const (??)
    public static int64 MIN = 1;
    public static int64 MAX = int32.MAX;
    public static int64 INVALID = -1;
    
    public UID(int64 value) {
        base (value);
    }
    
    public bool is_valid() {
        return is_value_valid(value);
    }
    
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

