/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A generic IMAP message or mailbox flag.
 *
 * In IMAP, message and mailbox flags have similar syntax, which is encapsulated here.
 *
 * @see MessageFlag
 * @see MailboxAttribute
 */

public abstract class Geary.Imap.Flag : BaseObject, Gee.Hashable<Geary.Imap.Flag> {
    public string value { get; private set; }
    
    public Flag(string value) {
        this.value = value;
    }
    
    public bool is_system() {
        return value[0] == '\\';
    }
    
    public bool equals_string(string value) {
        return this.value.down() == value.down();
    }
    
    public bool equal_to(Geary.Imap.Flag flag) {
        return (flag == this) ? true : flag.equals_string(value);
    }
    
    public uint hash() {
        return str_hash(value.down());
    }
    
    public string to_string() {
        return value;
    }
}



