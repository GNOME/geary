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
     * Returns a valid UID, which means returning MIN or MAX if the value is out of range (either
     * direction) or MAX if this value is already MAX.
     */
    public UID next() {
        if (value < MIN)
            return new UID(MIN);
        else if (value > MAX)
            return new UID(MAX);
        else
            return new UID(Numeric.int64_ceiling(value + 1, MAX));
    }
    
    /**
     * Returns a valid UID, which means returning MIN or MAX if the value is out of range (either
     * direction) or MIN if this value is already MIN.
     */
    public UID previous() {
        if (value < MIN)
            return new UID(MIN);
        else if (value > MAX)
            return new UID(MAX);
        else
            return new UID(Numeric.int64_floor(value - 1, MIN));
    }
    
    public virtual int compare_to(Geary.Imap.UID other) {
        if (value < other.value)
            return -1;
        else if (value > other.value)
            return 1;
        else
            return 0;
    }
    
    public string serialize() {
        return value.to_string();
    }
}

