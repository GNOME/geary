/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.EmailProperties : Object {
    // Flags that can be set or cleared on a given e-mail.
    public enum EmailFlags {
        NONE   =  0,
        UNREAD =  1 << 0;
        
        public inline bool is_all_set(EmailFlags required_flags) {
            return (this & required_flags) == required_flags;
        }
        
        public inline EmailFlags set(EmailFlags flags) {
            return (this | flags);
        }
        
        public inline EmailFlags clear(EmailFlags flags) {
            return (this & ~(flags));
        }
        
        // Convenience method to check if the unread flag is set.
        public inline bool is_unread() {
            return is_all_set(UNREAD);
        }
    }
    
    // Flags se on the email object.
    public EmailFlags email_flags { get; protected set; default = EmailFlags.NONE; }
    
    public EmailProperties() {
    }
}

