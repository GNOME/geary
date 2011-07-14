/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.EmailProperties : Geary.EmailProperties {
    public MessageFlags flags { get; private set; }
    
    public EmailProperties(MessageFlags flags) {
        this.flags = flags;
    }
    
    public override bool is_unread() {
        return !flags.contains(MessageFlag.SEEN);
    }
}

