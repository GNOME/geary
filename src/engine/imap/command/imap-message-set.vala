/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern void qsort(void *base, size_t num, size_t size, CompareFunc compare_func);

/**
 * A represenation of an IMAP message range specifier.
 *
 * A MessageSet can be for {@link SequenceNumber}s (which use positional addressing) or
 * {@link UID}s.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-9]], "sequence-set" and "seq-range".
 */

public class Geary.Imap.MessageSet : BaseObject {
    /**
     * True if the {@link MessageSet} was created with a UID or a UID range.
     *
     * For {@link Command}s that accept MessageSets, they will use a UID variant
     */
    public bool is_uid { get; private set; default = false; }
    
    private string value { get; private set; }
    
    public MessageSet(SequenceNumber seq_num) {
        assert(seq_num.value > 0);
        
        value = seq_num.serialize();
    }
    
    public MessageSet.uid(UID uid) {
        assert(uid.value > 0);
        
        value = uid.serialize();
        is_uid = true;
    }
    
    public MessageSet.email_id(Geary.EmailIdentifier email_id) {
        MessageSet.uid(((Geary.Imap.EmailIdentifier) email_id).uid);
    }
    
    public MessageSet.range_by_count(SequenceNumber low_seq_num, int count) {
        assert(low_seq_num.value > 0);
        assert(count > 0);
        
        value = (count > 1)
            ? "%d:%d".printf(low_seq_num.value, low_seq_num.value + count - 1)
            : low_seq_num.serialize();
    }
    
    public MessageSet.range_by_first_last(SequenceNumber low_seq_num, SequenceNumber high_seq_num) {
        assert(low_seq_num.value > 0);
        assert(high_seq_num.value > 0);
        
        // correct range problems (i.e. last before first)
        if (low_seq_num.value > high_seq_num.value) {
            SequenceNumber swap = low_seq_num;
            low_seq_num = high_seq_num;
            high_seq_num = swap;
        }
        
        value = (!low_seq_num.equal_to(high_seq_num))
            ? "%s:%s".printf(low_seq_num.serialize(), high_seq_num.serialize())
            : low_seq_num.serialize();
    }
    
    public MessageSet.uid_range(UID low, UID high) {
        assert(low.value > 0);
        assert(high.value > 0);
        
        if (low.equal_to(high))
            value = low.serialize();
        else
            value = "%s:%s".printf(low.serialize(), high.serialize());
        
        is_uid = true;
    }
    
    public MessageSet.range_to_highest(SequenceNumber low_seq_num) {
        assert(low_seq_num.value > 0);
        
        value = "%s:*".printf(low_seq_num.serialize());
    }
    
    /**
     * A positive count yields a range going from initial up the stack (toward the most recently
     * added message).  A negative count yields a range going from initial down the stack (toward
     * the earliest added message).  A count of zero yields a message range for one UID, initial.
     *
     * Underflows and overflows are accounted for by clamping the arithmetic result to the possible
     * range of UID's.
     */
    public MessageSet.uid_range_by_count(UID initial, int count) {
        assert(initial.value > 0);
        
        if (count == 0) {
            value = initial.serialize();
        } else {
            int64 low, high;
            if (count < 0) {
                high = initial.value;
                low = (high + count).clamp(1, uint32.MAX);
            } else {
                // count > 0
                low = initial.value;
                high = (low + count).clamp(1, uint32.MAX);
            }
            
            value = "%s:%s".printf(low.to_string(), high.to_string());
        }
        
        is_uid = true;
    }
    
    public MessageSet.uid_range_to_highest(UID low) {
        assert(low.value > 0);
        
        value = "%s:*".printf(low.serialize());
        is_uid = true;
    }
    
    public MessageSet.sparse(SequenceNumber[] seq_nums) {
        value = build_sparse_range(seq_array_to_int64(seq_nums));
    }
    
    public MessageSet.uid_sparse(UID[] msg_uids) {
        value = build_sparse_range(uid_array_to_int64(msg_uids));
        is_uid = true;
    }
    
    public MessageSet.email_id_collection(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        assert(email_ids.size > 0);
        
        value = build_sparse_range(email_id_collection_to_int64(email_ids));
        is_uid = true;
    }
    
    public MessageSet.sparse_to_highest(SequenceNumber[] seq_nums) {
        value = "%s:*".printf(build_sparse_range(seq_array_to_int64(seq_nums)));
    }
    
    public MessageSet.multirange(MessageSet[] msg_sets) {
        StringBuilder builder = new StringBuilder();
        for (int ctr = 0; ctr < msg_sets.length; ctr++) {
            unowned MessageSet msg_set = msg_sets[ctr];
            
            if (ctr < (msg_sets.length - 1))
                builder.append_printf("%s:", msg_set.value);
            else
                builder.append(msg_set.value);
        }
        
        value = builder.str;
    }
    
    public MessageSet.multisparse(MessageSet[] msg_sets) {
        StringBuilder builder = new StringBuilder();
        for (int ctr = 0; ctr < msg_sets.length; ctr++) {
            unowned MessageSet msg_set = msg_sets[ctr];
            
            if (ctr < (msg_sets.length - 1))
                builder.append_printf("%s,", msg_set.value);
            else
                builder.append(msg_set.value);
        }
        
        value = builder.str;
    }
    
    public MessageSet.custom(string custom) {
        value = custom;
    }
    
    public MessageSet.uid_custom(string custom) {
        value = custom;
        is_uid = true;
    }
    
    // Builds sparse range of either UID values or message numbers.
    // NOTE: This method assumes the supplied array is internally allocated, and so an in-place sort
    // is allowable
    private static string build_sparse_range(int64[] seq_nums) {
        assert(seq_nums.length > 0);
        
        // sort array to search for spans
        qsort(seq_nums, seq_nums.length, sizeof(int64), Numeric.int64_compare);
        
        int64 start_of_span = -1;
        int64 last_seq_num = -1;
        int span_count = 0;
        StringBuilder builder = new StringBuilder();
        foreach (int64 seq_num in seq_nums) {
            assert(seq_num >= 0);
            
            // the first number is automatically the start of a span, although it may be a span of one
            // (start_of_span < 0 should only happen on first iteration; can't easily break out of
            // loop because foreach/Iterator would still require a special case to skip it)
            if (start_of_span < 0) {
                // start of first span
                builder.append(seq_num.to_string());
                
                start_of_span = seq_num;
                span_count = 1;
            } else if ((start_of_span + span_count) == seq_num) {
                // span continues
                span_count++;
            } else {
                assert(span_count >= 1);
                
                // span ends, another begins
                if (span_count == 1) {
                    builder.append_printf(",%s", seq_num.to_string());
                } else if (span_count == 2) {
                    builder.append_printf(",%s,%s", (start_of_span + 1).to_string(),
                        seq_num.to_string());
                } else {
                    builder.append_printf(":%s,%s", (start_of_span + span_count - 1).to_string(),
                        seq_num.to_string());
                }
                
                start_of_span = seq_num;
                span_count = 1;
            }
            
            last_seq_num = seq_num;
        }
        
        // there should always be one seq_num in sorted, so the loop should exit with some state
        assert(start_of_span >= 0);
        assert(span_count > 0);
        assert(last_seq_num >= 0);
        
        // look for open-ended span
        if (span_count == 2)
            builder.append_printf(",%s", last_seq_num.to_string());
        else
            builder.append_printf(":%s", last_seq_num.to_string());
        
        return builder.str;
    }
    
    private static int64[] seq_array_to_int64(SequenceNumber[] seq_nums) {
        int64[] ret = new int64[0];
        foreach (SequenceNumber seq_num in seq_nums)
            ret += (int64) seq_num.value;
        
        return ret;
    }
    
    private static int64[] uid_array_to_int64(UID[] msg_uids) {
        int64[] ret = new int64[0];
        foreach (UID uid in msg_uids)
            ret += uid.value;
        
        return ret;
    }
    
    private static int64[] email_id_collection_to_int64(Gee.Collection<Geary.EmailIdentifier> email_ids) {
        int64[] ret = new int64[0];
        foreach (Geary.EmailIdentifier email_id in email_ids)
            ret += ((Geary.Imap.EmailIdentifier) email_id).uid.value;
        
        return ret;
    }
    
    /**
     * Returns the {@link MessageSet} as a {@link Parameter} suitable for inclusion in a
     * {@link Command}.
     */
    public Parameter to_parameter() {
        // Message sets are not quoted, even if they use an atom-special character (this *might*
        // be a Gmailism...)
        return new UnquotedStringParameter(value);
    }
    
    public string to_string() {
        return value;
    }
}

