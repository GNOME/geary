/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.EmailFlags : Geary.EmailFlags {
    public MessageFlags message_flags { get; private set; }
    
    public EmailFlags(MessageFlags flags) {
        message_flags = flags;
        
        if (!flags.contains(MessageFlag.SEEN))
            add(UNREAD);
    }
    
    public override void add(EmailFlag flag) {
        if (flag.equals(UNREAD))
            message_flags.remove(MessageFlag.SEEN);
        
        base.add(flag);
    }
    
    public override bool remove(EmailFlag flag) {
        if (flag.equals(UNREAD))
            message_flags.add(MessageFlag.SEEN);
        
        return base.remove(flag);
    }
}

