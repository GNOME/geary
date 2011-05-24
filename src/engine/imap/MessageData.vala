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
 * lists (Flag, Attribute).  Obviously these classes are closely related, hence their presence
 * here.
 *
 * Also note that Imap.MessageData inherits from Common.MessageData.
 */

public interface Geary.Imap.MessageData : Geary.Common.MessageData {
}

public class Geary.Imap.UID : Geary.Common.IntMessageData, Geary.Imap.MessageData {
    public UID(int value) {
        base (value);
    }
}

public class Geary.Imap.MessageNumber : Geary.Common.IntMessageData, Geary.Imap.MessageData {
    public MessageNumber(int value) {
        base (value);
    }
}

public class Geary.Imap.Flag {
    public static Flag ANSWERED = new Flag("\\answered");
    public static Flag DELETED = new Flag("\\deleted");
    public static Flag DRAFT = new Flag("\\draft");
    public static Flag FLAGGED = new Flag("\\flagged");
    public static Flag RECENT = new Flag("\\recent");
    public static Flag SEEN = new Flag("\\seen");
    
    public string value { get; private set; }
    
    public Flag(string value) {
        this.value = value;
    }
    
    public bool is_system() {
        return value[0] == '\\';
    }
    
    public bool has_value(string value) {
        return this.value.down() == value.down();
    }
    
    public bool equals(Flag flag) {
        return (flag == this) ? true : flag.has_value(value);
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

public class Geary.Imap.Flags : Geary.Common.MessageData, Geary.Imap.MessageData {
    private Gee.Set<Flag> list;
    
    public Flags(Gee.Collection<Flag> flags) {
        list = new Gee.HashSet<Flag>(Flag.hash_func, Flag.equal_func);
        list.add_all(flags);
    }
    
    public bool contains(Flag flag) {
        return list.contains(flag);
    }
    
    public Gee.Set<Flag> get_all() {
        return list.read_only_view;
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

public class Geary.Imap.InternalDate : Geary.RFC822.Date, Geary.Imap.MessageData {
    public InternalDate(string value) {
        base (value);
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
    public Geary.RFC822.MessageID message_id { get; private set; }
    
    public Envelope(Geary.RFC822.Date sent, Geary.RFC822.Subject subject,
        Geary.RFC822.MailboxAddresses from, Geary.RFC822.MailboxAddresses sender,
        Geary.RFC822.MailboxAddresses? reply_to, Geary.RFC822.MailboxAddresses? to,
        Geary.RFC822.MailboxAddresses? cc, Geary.RFC822.MailboxAddresses? bcc,
        Geary.RFC822.MessageID? in_reply_to, Geary.RFC822.MessageID message_id) {
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

