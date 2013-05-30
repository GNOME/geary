/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * MessageData is an IMAP data structure delivered in some form by the server to the client.
 * Although the primary use of this object is for FETCH results, other commands return 
 * similarly-structured data (in particulars Flags and Attributes).
 * 
 * Note that IMAP specifies that Flags and Attributes are *always* returned as a list, even if only
 * one is present, which is why these elements are MessageData but not the elements within the
 * lists (Flag, Attribute).
 *
 * Also note that Imap.MessageData requires {@link Geary.MessageData.AbstractMessageData}.
 */

public interface Geary.Imap.MessageData : Geary.MessageData.AbstractMessageData {
}

public class Geary.Imap.UID : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData,
    Gee.Comparable<Geary.Imap.UID> {
    // Using statics because int32.MAX is static, not const (??)
    public static int64 MIN = 1;
    public static int64 MAX = int32.MAX;
    public static int64 INVALID = -1;
    
    public UID(int64 value) {
        base (value);
    }
    
    public bool is_valid() {
        return is_value_valid(value);
    }
    
    public static bool is_value_valid(int64 val) {
        return Numeric.int64_in_range_inclusive(val, MIN, MAX);
    }
    
    /**
     * Returns a valid UID, which means returning MIN or MAX if the value is out of range (either
     * direction) or MAX if this value is already MAX.
     */
    public UID next() {
        if (value < MIN)
            return new UID(MIN);
        else if (value > MAX)
            return new UID(MAX);
        else
            return new UID(Numeric.int64_ceiling(value + 1, MAX));
    }
    
    /**
     * Returns a valid UID, which means returning MIN or MAX if the value is out of range (either
     * direction) or MIN if this value is already MIN.
     */
    public UID previous() {
        if (value < MIN)
            return new UID(MIN);
        else if (value > MAX)
            return new UID(MAX);
        else
            return new UID(Numeric.int64_floor(value - 1, MIN));
    }
    
    public virtual int compare_to(Geary.Imap.UID other) {
        if (value < other.value)
            return -1;
        else if (value > other.value)
            return 1;
        else
            return 0;
    }
}

public class Geary.Imap.UIDValidity : Geary.MessageData.Int64MessageData, Geary.Imap.MessageData {
    // Using statics because int32.MAX is static, not const (??)
    public static int64 MIN = 1;
    public static int64 MAX = int32.MAX;
    public static int64 INVALID = -1;
    
    public UIDValidity(int64 value) {
        base (value);
    }
}

public class Geary.Imap.MessageNumber : Geary.MessageData.IntMessageData, Geary.Imap.MessageData,
    Gee.Comparable<MessageNumber> {
    public MessageNumber(int value) {
        base (value);
    }
    
    public virtual int compare_to(MessageNumber other) {
        return value - other.value;
    }
}

public abstract class Geary.Imap.Flags : Geary.MessageData.AbstractMessageData, Geary.Imap.MessageData,
    Gee.Hashable<Geary.Imap.Flags> {
    public int size { get { return list.size; } }
    
    protected Gee.Set<Flag> list;
    
    public Flags(Gee.Collection<Flag> flags) {
        list = new Gee.HashSet<Flag>();
        list.add_all(flags);
    }
    
    public bool contains(Flag flag) {
        return list.contains(flag);
    }
    
    public Gee.Set<Flag> get_all() {
        return list.read_only_view;
    }
    
    /**
     * Returns the flags in serialized form, which is each flag separated by a space (legal in
     * IMAP, as flags must be atoms and atoms prohibit spaces).
     */
    public virtual string serialize() {
        return to_string();
    }
    
    public bool equal_to(Geary.Imap.Flags other) {
        if (this == other)
            return true;
        
        if (other.size != size)
            return false;
        
        foreach (Flag flag in list) {
            if (!other.contains(flag))
                return false;
        }
        
        return true;
    }
    
    public override string to_string() {
        StringBuilder builder = new StringBuilder();
        foreach (Flag flag in list) {
            if (!String.is_empty(builder.str))
                builder.append_c(' ');
            
            builder.append(flag.value);
        }
        
        return builder.str;
    }
    
    public uint hash() {
        return to_string().hash();
    }
}

public class Geary.Imap.MessageFlags : Geary.Imap.Flags {
    public MessageFlags(Gee.Collection<MessageFlag> flags) {
        base (flags);
    }
    
    public static MessageFlags from_list(ListParameter listp) throws ImapError {
        Gee.Collection<MessageFlag> list = new Gee.ArrayList<MessageFlag>();
        for (int ctr = 0; ctr < listp.get_count(); ctr++)
            list.add(new MessageFlag(listp.get_as_string(ctr).value));
        
        return new MessageFlags(list);
    }
    
    public static MessageFlags deserialize(string str) {
        string[] tokens = str.split(" ");
        
        Gee.Collection<MessageFlag> flags = new Gee.ArrayList<MessageFlag>();
        foreach (string token in tokens)
            flags.add(new MessageFlag(token));
        
        return new MessageFlags(flags);
    }
    
    internal void add(MessageFlag flag) {
        list.add(flag);
    }
    
    internal void remove(MessageFlag flag) {
        list.remove(flag);
    }
}

public class Geary.Imap.MailboxAttributes : Geary.Imap.Flags {
    public MailboxAttributes(Gee.Collection<MailboxAttribute> attrs) {
        base (attrs);
    }
    
    public static MailboxAttributes from_list(ListParameter listp) throws ImapError {
        Gee.Collection<MailboxAttribute> list = new Gee.ArrayList<MailboxAttribute>();
        for (int ctr = 0; ctr < listp.get_count(); ctr++)
            list.add(new MailboxAttribute(listp.get_as_string(ctr).value));
        
        return new MailboxAttributes(list);
    }
    
    public static MailboxAttributes deserialize(string str) {
        string[] tokens = str.split(" ");
        
        Gee.Collection<MailboxAttribute> attrs = new Gee.ArrayList<MailboxAttribute>();
        foreach (string token in tokens)
            attrs.add(new MailboxAttribute(token));
        
        return new MailboxAttributes(attrs);
    }
    
    public Geary.SpecialFolderType get_special_folder_type() {
        if (contains(MailboxAttribute.SPECIAL_FOLDER_INBOX))
            return Geary.SpecialFolderType.INBOX;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_ALL_MAIL))
            return Geary.SpecialFolderType.ALL_MAIL;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_TRASH))
            return Geary.SpecialFolderType.TRASH;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_DRAFTS))
            return Geary.SpecialFolderType.DRAFTS;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_SENT))
            return Geary.SpecialFolderType.SENT;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_SPAM))
            return Geary.SpecialFolderType.SPAM;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_STARRED))
            return Geary.SpecialFolderType.FLAGGED;
        
        if (contains(MailboxAttribute.SPECIAL_FOLDER_IMPORTANT))
            return Geary.SpecialFolderType.IMPORTANT;
        
        return Geary.SpecialFolderType.NONE;
    }
}

public class Geary.Imap.InternalDate : Geary.RFC822.Date, Geary.Imap.MessageData {
    public InternalDate(string iso8601) throws ImapError {
        base (iso8601);
    }
}

public class Geary.Imap.RFC822Size : Geary.RFC822.Size, Geary.Imap.MessageData {
    public RFC822Size(long value) {
        base (value);
    }
}

public class Geary.Imap.Envelope : Geary.MessageData.AbstractMessageData, Geary.Imap.MessageData {
    public Geary.RFC822.Date? sent { get; private set; }
    public Geary.RFC822.Subject subject { get; private set; }
    public Geary.RFC822.MailboxAddresses from { get; private set; }
    public Geary.RFC822.MailboxAddresses sender { get; private set; }
    public Geary.RFC822.MailboxAddresses? reply_to { get; private set; }
    public Geary.RFC822.MailboxAddresses? to { get; private set; }
    public Geary.RFC822.MailboxAddresses? cc { get; private set; }
    public Geary.RFC822.MailboxAddresses? bcc { get; private set; }
    public Geary.RFC822.MessageID? in_reply_to { get; private set; }
    public Geary.RFC822.MessageID? message_id { get; private set; }
    
    public Envelope(Geary.RFC822.Date? sent, Geary.RFC822.Subject subject,
        Geary.RFC822.MailboxAddresses from, Geary.RFC822.MailboxAddresses sender,
        Geary.RFC822.MailboxAddresses? reply_to, Geary.RFC822.MailboxAddresses? to,
        Geary.RFC822.MailboxAddresses? cc, Geary.RFC822.MailboxAddresses? bcc,
        Geary.RFC822.MessageID? in_reply_to, Geary.RFC822.MessageID? message_id) {
        this.sent = sent;
        this.subject = subject;
        this.from = from;
        this.sender = sender;
        this.reply_to = reply_to;
        this.to = to;
        this.cc = cc;
        this.bcc = bcc;
        this.in_reply_to = in_reply_to;
        this.message_id = message_id;
    }
    
    public override string to_string() {
        return "[%s] %s: \"%s\"".printf((sent != null) ? sent.to_string() : "(no date)",
            from.to_string(), subject.to_string());
    }
}

public class Geary.Imap.RFC822Header : Geary.RFC822.Header, Geary.Imap.MessageData {
    public RFC822Header(Geary.Memory.AbstractBuffer buffer) {
        base (buffer);
    }
}

public class Geary.Imap.RFC822Text : Geary.RFC822.Text, Geary.Imap.MessageData {
    public RFC822Text(Geary.Memory.AbstractBuffer buffer) {
        base (buffer);
    }
}

public class Geary.Imap.RFC822Full : Geary.RFC822.Full, Geary.Imap.MessageData {
    public RFC822Full(Geary.Memory.AbstractBuffer buffer) {
        base (buffer);
    }
}

