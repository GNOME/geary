/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representations of IMAP's INTERNALDATE field.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.3.3]]
 */

public class Geary.Imap.InternalDate : Geary.MessageData.AbstractMessageData, Geary.Imap.MessageData,
    Gee.Hashable<InternalDate>, Gee.Comparable<InternalDate> {
    public DateTime value { get; private set; }
    public time_t as_time_t { get; private set; }
    
    public InternalDate(string internaldate) throws ImapError {
        as_time_t = GMime.utils_header_decode_date(internaldate, null);
        if (as_time_t == 0) {
            throw new ImapError.PARSE_ERROR("Unable to parse \"%s\": not INTERNALDATE format",
                internaldate);
        }
        
        value = new DateTime.from_unix_local(as_time_t);
    }
    
    public InternalDate.from_date_time(DateTime datetime) throws ImapError {
        value = datetime;
    }
    
    /**
     * Returns the {@link InternalDate} as a {@link Parameter}.
     */
    public Parameter to_parameter() {
        return StringParameter.get_best_for(serialize());
    }
    
    /**
     * Returns the {@link InternalDate} as a {@link Parameter} for a {@link SearchCriterion}.
     *
     * @see serialize_for_search
     */
    public Parameter to_search_parameter() {
        return StringParameter.get_best_for(serialize_for_search());
    }
    
    /**
     * Returns the {@link InternalDate}'s string representation.
     *
     * @see serialize_for_search
     */
    public string serialize() {
        return value.format("%d-%b-%Y %H:%M:%S %z");
    }
    
    /**
     * Returns the {@link InternalDate}'s string representation for a SEARCH function.
     *
     * SEARCH does not respect time or timezone, so drop when sending it.  See
     * [[http://tools.ietf.org/html/rfc3501#section-6.4.4]]
     *
     * @see serialize
     */
    public string serialize_for_search() {
        return value.format("%d-%b-%Y");
    }
    
    public uint hash() {
        return value.hash();
    }
    
    public bool equal_to(InternalDate other) {
        return value.equal(other.value);
    }
    
    public int compare_to(InternalDate other) {
        return value.compare(other.value);
    }
    
    public override string to_string() {
        return serialize();
    }
}

