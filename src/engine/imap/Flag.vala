/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Flag {
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
    
    public bool equals(Flag flag) {
        return (flag == this) ? true : flag.equals_string(value);
    }
    
    public string to_string() {
        return value;
    }
    
    public static uint hash_func(void *flag) {
        return str_hash(((Flag *) flag)->value);
    }
    
    public static bool equal_func(void *a, void *b) {
        return ((Flag *) a)->equals((Flag *) b);
    }
}

public class Geary.Imap.MessageFlag : Geary.Imap.Flag {
    public static MessageFlag ANSWERED = new MessageFlag("\\answered");
    public static MessageFlag DELETED = new MessageFlag("\\deleted");
    public static MessageFlag DRAFT = new MessageFlag("\\draft");
    public static MessageFlag FLAGGED = new MessageFlag("\\flagged");
    public static MessageFlag RECENT = new MessageFlag("\\recent");
    public static MessageFlag SEEN = new MessageFlag("\\seen");
    public static MessageFlag ALLOWS_NEW = new MessageFlag("\\*");
    
    public MessageFlag(string value) {
        base (value);
    }
}

public class Geary.Imap.MailboxAttribute : Geary.Imap.Flag {
    public static MailboxAttribute NO_INFERIORS = new MailboxAttribute("\\noinferiors");
    public static MailboxAttribute NO_SELECT = new MailboxAttribute("\\noselect");
    public static MailboxAttribute MARKED = new MailboxAttribute("\\marked");
    public static MailboxAttribute UNMARKED = new MailboxAttribute("\\unmarked");
    public static MailboxAttribute HAS_NO_CHILDREN = new MailboxAttribute("\\hasnochildren");
    public static MailboxAttribute ALLOWS_NEW = new MailboxAttribute("\\*");
    
    public MailboxAttribute(string value) {
        base (value);
    }
}

