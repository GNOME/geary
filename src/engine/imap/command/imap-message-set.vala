/* Copyright 2011-2014 Yorba Foundation
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
    // 2^32 in base 10 requires ten bytes (characters) on the wire plus a separator between each
    // one, i.e. ~11 bytes per seqnum or UID ... to keep lists below server maximums, this value
    // is set to keep max. command length somewhere under 1K (including tag, command, parameters,
    // etc.)
    private const int MAX_SPARSE_VALUES_PER_SET = 50;
    
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
        
        // correct ordering
        if (low.value > high.value) {
            UID swap = low;
            low = high;
            high = swap;
        }
        
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
    
    public MessageSet.uid_range_to_highest(UID low) {
        assert(low.value > 0);
        
        value = "%s:*".printf(low.serialize());
        is_uid = true;
    }
    
    public MessageSet.custom(string custom) {
        value = custom;
    }
    
    public MessageSet.uid_custom(string custom) {
        value = custom;
        is_uid = true;
    }
    
    /**
     * Convert a collection of {@link SequenceNumber}s into a list of {@link MessageSet}s.
     *
     * Although this could return a single MessageSet, large collections could create an IMAP
     * command beyond the server maximum, and so they will be broken up into multiple sets.
     */
    public static Gee.List<MessageSet> sparse(Gee.Collection<SequenceNumber> seq_nums) {
        return build_sparse_sets(seq_array_to_int64(seq_nums), false);
    }
    
    /**
     * Convert a collection of {@link UID}s into a list of {@link MessageSet}s.
     *
     * Although this could return a single MessageSet, large collections could create an IMAP
     * command beyond the server maximum, and so they will be broken up into multiple sets.
     */
    public static Gee.List<MessageSet> uid_sparse(Gee.Collection<UID> msg_uids) {
        return build_sparse_sets(uid_array_to_int64(msg_uids), true);
    }
    
    // create zero or more MessageSets of no more than MAX_SPARSE_VALUES_PER_SET UIDs/sequence
    // numbers
    private static Gee.List<MessageSet> build_sparse_sets(int64[] sorted, bool is_uid) {
        Gee.List<MessageSet> list = new Gee.ArrayList<MessageSet>();
        
        int start = 0;
        for (;;) {
            if (start >= sorted.length)
                break;
            
            int end = (start + MAX_SPARSE_VALUES_PER_SET).clamp(0, sorted.length);
            unowned int64[] slice = sorted[start:end];
            
            string sparse_range = build_sparse_range(slice);
            list.add(is_uid ? new MessageSet.uid_custom(sparse_range) : new MessageSet.custom(sparse_range));
            
            start = end;
        }
        
        return list;
    }
    
    // Builds sparse range of either UID values or sequence numbers.  Values should be sorted before
    // calling to maximum finding runs.
    private static string build_sparse_range(int64[] seq_nums) {
        assert(seq_nums.length > 0);
        
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
        else if (last_seq_num != start_of_span)
            builder.append_printf(":%s", last_seq_num.to_string());
        
        return builder.str;
    }
    
    private static int64[] seq_array_to_int64(Gee.Collection<SequenceNumber> seq_nums) {
        // guarantee sorted (to maximum finding runs in build_sparse_range())
        Gee.TreeSet<SequenceNumber> sorted = new Gee.TreeSet<SequenceNumber>();
        sorted.add_all(seq_nums);
        
        // build sorted array
        int64[] ret = new int64[sorted.size];
        int index = 0;
        foreach (SequenceNumber seq_num in sorted)
            ret[index++] = (int64) seq_num.value;
        
        return ret;
    }
    
    private static int64[] uid_array_to_int64(Gee.Collection<UID> msg_uids) {
        // guarantee sorted (to maximize finding runs in build_sparse_range())
        Gee.TreeSet<UID> sorted = new Gee.TreeSet<UID>();
        sorted.add_all(msg_uids);
        
        // build sorted array
        int64[] ret = new int64[sorted.size];
        int index = 0;
        foreach (UID uid in sorted)
            ret[index++] = uid.value;
        
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
        return "%s::%s".printf(is_uid ? "UID" : "pos", value);
    }
}

