/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.MessageSet {
    public bool is_uid { get; private set; default = false; }
    
    private string value { get; private set; }
    
    public MessageSet(int msg_num) {
        assert(msg_num > 0);
        
        value = "%d".printf(msg_num);
    }
    
    public MessageSet.uid(UID uid) {
        assert(uid.value > 0);
        
        value = "%lld".printf(uid.value);
        is_uid = true;
    }
    
    public MessageSet.email_id(Geary.EmailIdentifier email_id) {
        MessageSet.uid(((Geary.Imap.EmailIdentifier) email_id).uid);
    }
    
    public MessageSet.range(int low_msg_num, int count) {
        assert(low_msg_num > 0);
        assert(count > 0);
        
        value = (count > 1)
            ? "%d:%d".printf(low_msg_num, low_msg_num + count - 1)
            : "%d".printf(low_msg_num);
    }
    
    public MessageSet.uid_range(UID low, UID high) {
        assert(low.value > 0);
        assert(high.value > 0);
        
        value = "%lld:%lld".printf(low.value, high.value);
        is_uid = true;
    }
    
    public MessageSet.range_to_highest(int low_msg_num) {
        assert(low_msg_num > 0);
        
        value = "%d:*".printf(low_msg_num);
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
            MessageSet.uid(initial);
            
            return;
        }
        
        int64 low, high;
        if (count < 0) {
            high = initial.value;
            low = (high + count).clamp(1, uint32.MAX);
        } else {
            // count > 0
            low = initial.value;
            high = (low + count).clamp(1, uint32.MAX);
        }
        
        value = "%lld:%lld".printf(low, high);
        is_uid = true;
    }
    
    public MessageSet.uid_range_to_highest(UID low) {
        assert(low.value > 0);
        
        value = "%lld:*".printf(low.value);
        is_uid = true;
    }
    
    public MessageSet.sparse(int[] msg_nums) {
        value = build_sparse_range(msg_array_to_int64(msg_nums));
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
    
    public MessageSet.sparse_to_highest(int[] msg_nums) {
        value = "%s:*".printf(build_sparse_range(msg_array_to_int64(msg_nums)));
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
    // TODO: It would be more efficient to look for runs in the numbers and form the set specifier
    // with them.
    private static string build_sparse_range(int64[] msg_nums) {
        assert(msg_nums.length > 0);
        
        StringBuilder builder = new StringBuilder();
        for (int ctr = 0; ctr < msg_nums.length; ctr++) {
            int64 msg_num = msg_nums[ctr];
            assert(msg_num >= 0);
            
            if (ctr < (msg_nums.length - 1))
                builder.append_printf("%lld,", msg_num);
            else
                builder.append_printf("%lld", msg_num);
        }
        
        return builder.str;
    }
    
    private static int64[] msg_array_to_int64(int[] msg_nums) {
        int64[] ret = new int64[0];
        foreach (int num in msg_nums)
            ret += (int64) num;
        
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
    
    public Parameter to_parameter() {
        // Message sets are not quoted, even if they use an atom-special character (this *might*
        // be a Gmailism...)
        return new UnquotedStringParameter(value);
    }
    
    public string to_string() {
        return value;
    }
}

