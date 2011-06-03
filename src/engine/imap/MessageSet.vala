/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.MessageSet {
    public string value { get; private set; }
    
    public MessageSet(int msg_num) {
        assert(msg_num >= 0);
        
        value = "%d".printf(msg_num);
    }
    
    public MessageSet.range(int low_msg_num, int count) {
        assert(low_msg_num > 0);
        assert(count > 0);
        
        value = (count > 1)
            ? "%d:%d".printf(low_msg_num, low_msg_num + count - 1)
            : "%d".printf(low_msg_num);
    }
    
    public MessageSet.range_to_highest(int low_msg_num) {
        assert(low_msg_num > 0);
        
        value = "%d:*".printf(low_msg_num);
    }
    
    public MessageSet.scattered(int[] msg_nums) {
        value = build_scattered_range(msg_nums);
    }
    
    public MessageSet.scattered_to_highest(int[] msg_nums) {
        value = "%s:*".printf(build_scattered_range(msg_nums));
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
    
    public MessageSet.multiscattered(MessageSet[] msg_sets) {
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
    
    private static string build_scattered_range(int[] msg_nums) {
        assert(msg_nums.length > 0);
        
        StringBuilder builder = new StringBuilder();
        for (int ctr = 0; ctr < msg_nums.length; ctr++) {
            int msg_num = msg_nums[ctr];
            assert(msg_num >= 0);
            
            if (ctr < (msg_nums.length - 1))
                builder.append_printf("%d,", msg_num);
            else
                builder.append_printf("%d", msg_num);
        }
        
        return builder.str;
    }
}

