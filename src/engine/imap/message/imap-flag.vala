/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Flag : BaseObject, Equalable, Hashable {
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
    
    public bool equals(Equalable b) {
        Flag? flag = b as Flag;
        if (flag == null)
            return false;
        
        return (flag == this) ? true : flag.equals_string(value);
    }
    
    public uint to_hash() {
        return str_hash(value.down());
    }
    
    public string to_string() {
        return value;
    }
}

public class Geary.Imap.MessageFlag : Geary.Imap.Flag {
    private static MessageFlag? _answered = null;
    public static MessageFlag ANSWERED { get {
        if (_answered == null)
            _answered = new MessageFlag("\\answered");
        
        return _answered;
    } }
    
    private static MessageFlag? _deleted = null;
    public static MessageFlag DELETED { get {
        if (_deleted == null)
            _deleted = new MessageFlag("\\deleted");
        
        return _deleted;
    } }
    
    private static MessageFlag? _draft = null;
    public static MessageFlag DRAFT { get {
        if (_draft == null)
            _draft = new MessageFlag("\\draft");
        
        return _draft;
    } }
    
    private static MessageFlag? _flagged = null;
    public static MessageFlag FLAGGED { get {
        if (_flagged == null)
            _flagged = new MessageFlag("\\flagged");
        
        return _flagged;
    } }
    
    private static MessageFlag? _recent = null;
    public static MessageFlag RECENT { get {
        if (_recent == null)
            _recent = new MessageFlag("\\recent");
        
        return _recent;
    } }
    
    private static MessageFlag? _seen = null;
    public static MessageFlag SEEN { get {
        if (_seen == null)
            _seen = new MessageFlag("\\seen");
        
        return _seen;
    } }
    
    private static MessageFlag? _allows_new = null;
    public static MessageFlag ALLOWS_NEW { get {
        if (_allows_new == null)
            _allows_new = new MessageFlag("\\*");
        
        return _allows_new;
    } }
    
    public MessageFlag(string value) {
        base (value);
    }
    
    // Call these at init time to prevent thread issues
    internal static void init() {
        MessageFlag to_init = ANSWERED;
        to_init = DELETED;
        to_init = DRAFT;
        to_init = FLAGGED;
        to_init = RECENT;
        to_init = SEEN;
        to_init = ALLOWS_NEW;
    }
    
    // Converts a list of email flags to add and remove to a list of message
    // flags to add and remove.
    public static void from_email_flags(Geary.EmailFlags? email_flags_add, 
        Geary.EmailFlags? email_flags_remove, out Gee.List<MessageFlag> msg_flags_add,
        out Gee.List<MessageFlag> msg_flags_remove) {
        msg_flags_add = new Gee.ArrayList<MessageFlag>();
        msg_flags_remove = new Gee.ArrayList<MessageFlag>();

        if (email_flags_add != null) {
            if (email_flags_add.contains(Geary.EmailFlags.UNREAD))
                msg_flags_remove.add(MessageFlag.SEEN);
            if (email_flags_add.contains(Geary.EmailFlags.FLAGGED))
                msg_flags_add.add(MessageFlag.FLAGGED);
        }

        if (email_flags_remove != null) {
            if (email_flags_remove.contains(Geary.EmailFlags.UNREAD))
                msg_flags_add.add(MessageFlag.SEEN);
            if (email_flags_remove.contains(Geary.EmailFlags.FLAGGED))
                msg_flags_remove.add(MessageFlag.FLAGGED);
        }
    }
}

public class Geary.Imap.MailboxAttribute : Geary.Imap.Flag {
    private static MailboxAttribute? _no_inferiors = null;
    public static MailboxAttribute NO_INFERIORS { get {
        if (_no_inferiors == null)
            _no_inferiors = new MailboxAttribute("\\noinferiors");
        
        return _no_inferiors;
    } }
    
    private static MailboxAttribute? _no_select = null;
    public static MailboxAttribute NO_SELECT { get {
        if (_no_select == null)
            _no_select = new MailboxAttribute("\\noselect");
        
        return _no_select;
    } }
    
    private static MailboxAttribute? _marked = null;
    public static MailboxAttribute MARKED { get {
        if (_marked == null)
            _marked = new MailboxAttribute("\\marked");
        
        return _marked;
    } }
    
    private static MailboxAttribute? _unmarked = null;
    public static MailboxAttribute UNMARKED { get {
        if (_unmarked == null)
            _unmarked = new MailboxAttribute("\\unmarked");
        
        return _unmarked;
    } }
    
    private static MailboxAttribute? _has_no_children = null;
    public static MailboxAttribute HAS_NO_CHILDREN { get {
        if (_has_no_children == null)
            _has_no_children = new MailboxAttribute("\\hasnochildren");
        
        return _has_no_children;
    } }
    
    private static MailboxAttribute? _has_children = null;
    public static MailboxAttribute HAS_CHILDREN { get {
        if (_has_children == null)
            _has_children = new MailboxAttribute("\\haschildren");
        
        return _has_children;
    } }
    
    private static MailboxAttribute? _allows_new = null;
    public static MailboxAttribute ALLOWS_NEW { get {
        if (_allows_new == null)
            _allows_new = new MailboxAttribute("\\*");
        
        return _allows_new;
    } }
    
    private static MailboxAttribute? _xlist_inbox = null;
    public static MailboxAttribute SPECIAL_FOLDER_INBOX { get {
        if (_xlist_inbox == null)
            _xlist_inbox = new MailboxAttribute("\\Inbox");
        
        return _xlist_inbox;
    } }
    
    private static MailboxAttribute? _xlist_all_mail = null;
    public static MailboxAttribute SPECIAL_FOLDER_ALL_MAIL { get {
        if (_xlist_all_mail == null)
            _xlist_all_mail = new MailboxAttribute("\\AllMail");
        
        return _xlist_all_mail;
    } }
    
    private static MailboxAttribute? _xlist_trash = null;
    public static MailboxAttribute SPECIAL_FOLDER_TRASH { get {
        if (_xlist_trash == null)
            _xlist_trash = new MailboxAttribute("\\Trash");
        
        return _xlist_trash;
    } }
    
    private static MailboxAttribute? _xlist_drafts = null;
    public static MailboxAttribute SPECIAL_FOLDER_DRAFTS { get {
        if (_xlist_drafts == null)
            _xlist_drafts = new MailboxAttribute("\\Drafts");
        
        return _xlist_drafts;
    } }

    private static MailboxAttribute? _xlist_sent = null;
    public static MailboxAttribute SPECIAL_FOLDER_SENT { get {
        if (_xlist_sent == null)
            _xlist_sent = new MailboxAttribute("\\Sent");
        
        return _xlist_sent;
    } }

    private static MailboxAttribute? _xlist_spam = null;
    public static MailboxAttribute SPECIAL_FOLDER_SPAM { get {
        if (_xlist_spam == null)
            _xlist_spam = new MailboxAttribute("\\Spam");
        
        return _xlist_spam;
    } }
    
    private static MailboxAttribute? _xlist_starred = null;
    public static MailboxAttribute SPECIAL_FOLDER_STARRED { get {
        if (_xlist_starred == null)
            _xlist_starred = new MailboxAttribute("\\Starred");
        
        return _xlist_starred;
    } }
    
    private static MailboxAttribute? _xlist_important = null;
    public static MailboxAttribute SPECIAL_FOLDER_IMPORTANT { get {
        if (_xlist_important == null)
            _xlist_important = new MailboxAttribute("\\Important");
        
        return _xlist_important;
    } }
    
    public MailboxAttribute(string value) {
        base (value);
    }
    
    // Call these at init time to prevent thread issues
    internal static void init() {
        MailboxAttribute to_init = NO_INFERIORS;
        to_init = NO_SELECT;
        to_init = MARKED;
        to_init = UNMARKED;
        to_init = HAS_NO_CHILDREN;
        to_init = HAS_CHILDREN;
        to_init = ALLOWS_NEW;
        to_init = SPECIAL_FOLDER_ALL_MAIL;
        to_init = SPECIAL_FOLDER_DRAFTS;
        to_init = SPECIAL_FOLDER_IMPORTANT;
        to_init = SPECIAL_FOLDER_INBOX;
        to_init = SPECIAL_FOLDER_SENT;
        to_init = SPECIAL_FOLDER_SPAM;
        to_init = SPECIAL_FOLDER_STARRED;
        to_init = SPECIAL_FOLDER_TRASH;
    }
}

