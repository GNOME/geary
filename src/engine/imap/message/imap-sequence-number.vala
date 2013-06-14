/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of IMAP's sequence number, i.e. positional addressing within a mailbox.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.3.1.2]]
 *
 * @see UID
 */

public class Geary.Imap.SequenceNumber : Geary.MessageData.IntMessageData, Geary.Imap.MessageData,
    Gee.Comparable<SequenceNumber> {
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
    
    public virtual int compare_to(SequenceNumber other) {
        return value - other.value;
    }
    
    public string serialize() {
        return value.to_string();
    }
}

