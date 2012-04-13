/* Copyright 2011-2012 Yorba Foundation
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
        if (flags.contains(MessageFlag.FLAGGED))
            add(FLAGGED);
    }

    public override void add(EmailFlag flag) {
        if (flag.equals(UNREAD))
            message_flags.remove(MessageFlag.SEEN);
        if (flag.equals(FLAGGED))
            message_flags.add(MessageFlag.FLAGGED);

        base.add(flag);
    }

    public override bool remove(EmailFlag flag) {
        if (flag.equals(UNREAD))
            message_flags.add(MessageFlag.SEEN);
        if (flag.equals(FLAGGED))
            message_flags.remove(MessageFlag.FLAGGED);

        return base.remove(flag);
    }
}

