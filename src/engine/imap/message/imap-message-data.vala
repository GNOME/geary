/* Copyright 2011 Yorba Foundation
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
 * Also note that Imap.MessageData inherits from Common.MessageData.
 */

public interface Geary.Imap.MessageData : Geary.Common.MessageData {
}

public class Geary.Imap.UID : Geary.Common.Int64MessageData, Geary.Imap.MessageData {
    public UID(int64 value) {
        base (value);
    }
    
    public bool is_valid() {
        return value >= 1;
    }
}

public class Geary.Imap.UIDValidity : Geary.Common.Int64MessageData, Geary.Imap.MessageData {
    public UIDValidity(int64 value) {
        base (value);
    }
}

public class Geary.Imap.MessageNumber : Geary.Common.IntMessageData, Geary.Imap.MessageData {
    public MessageNumber(int value) {
        base (value);
    }
}

public abstract class Geary.Imap.Flags : Geary.Common.MessageData, Geary.Imap.MessageData, Equalable {
    public int size { get { return list.size; } }
    
    protected Gee.Set<Flag> list;
    
    public Flags(Gee.Collection<Flag> flags) {
        list = new Gee.HashSet<Flag>(Hashable.hash_func, Equalable.equal_func);
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
    
    public bool equals(Equalable e) {
        Imap.Flags? other = e as Imap.Flags;
        if (other == null)
            return false;
        
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

public class Geary.Imap.Envelope : Geary.Common.MessageData, Geary.Imap.MessageData {
    public Geary.RFC822.Date sent { get; private set; }
    public Geary.RFC822.Subject subject { get; private set; }
    public Geary.RFC822.MailboxAddresses from { get; private set; }
    public Geary.RFC822.MailboxAddresses sender { get; private set; }
    public Geary.RFC822.MailboxAddresses? reply_to { get; private set; }
    public Geary.RFC822.MailboxAddresses? to { get; private set; }
    public Geary.RFC822.MailboxAddresses? cc { get; private set; }
    public Geary.RFC822.MailboxAddresses? bcc { get; private set; }
    public Geary.RFC822.MessageID? in_reply_to { get; private set; }
    public Geary.RFC822.MessageID? message_id { get; private set; }
    
    public Envelope(Geary.RFC822.Date sent, Geary.RFC822.Subject subject,
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
        return "[%s] %s: \"%s\"".printf(sent.to_string(), from.to_string(), subject.to_string());
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

