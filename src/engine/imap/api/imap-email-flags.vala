/* Copyright 2011-2013 Yorba Foundation
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
        
        if (flags.contains(MessageFlag.LOAD_REMOTE_IMAGES))
            add(LOAD_REMOTE_IMAGES);
    }
    
    protected override void notify_added(Gee.Collection<EmailFlag> added) {
        foreach (EmailFlag flag in added) {
            if (flag.equal_to(UNREAD))
                message_flags.remove(MessageFlag.SEEN);
            
            if (flag.equal_to(FLAGGED))
                message_flags.add(MessageFlag.FLAGGED);
            
            if (flag.equal_to(LOAD_REMOTE_IMAGES))
                message_flags.add(MessageFlag.LOAD_REMOTE_IMAGES);
        }
        
        base.notify_added(added);
    }
    
    protected override void notify_removed(Gee.Collection<EmailFlag> removed) {
        foreach (EmailFlag flag in removed) {
            if (flag.equal_to(UNREAD))
                message_flags.add(MessageFlag.SEEN);
            
            if (flag.equal_to(FLAGGED))
                message_flags.remove(MessageFlag.FLAGGED);
            
            if (flag.equal_to(LOAD_REMOTE_IMAGES))
                message_flags.remove(MessageFlag.LOAD_REMOTE_IMAGES);
        }
        
        base.notify_removed(removed);
    }
}

