/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Imap.Flag : Equalable, Hashable {
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
    
    private static MailboxAttribute? _allows_new = null;
    public static MailboxAttribute ALLOWS_NEW { get {
        if (_allows_new == null)
            _allows_new = new MailboxAttribute("\\*");
        
        return _allows_new;
    } }
    
    public MailboxAttribute(string value) {
        base (value);
    }
}

