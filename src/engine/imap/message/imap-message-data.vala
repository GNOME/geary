/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * MessageData is an IMAP data structure delivered in some form by the server to the client.
 *
 * Note that IMAP specifies that Flags and Attributes are *always* returned as a list, even if only
 * one is present, which is why these elements are MessageData but not the elements within the
 * lists (Flag, Attribute).
 *
 * Also note that Imap.MessageData requires {@link Geary.MessageData.AbstractMessageData}.
 *
 * TODO: Add an abstract to_parameter() method that can be used to serialize the message data.
 */

public interface Geary.Imap.MessageData : Geary.MessageData.AbstractMessageData {
}

/**
 * A representations of IMAP's INTERNALDATE field.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-2.3.3]]
 */

public class Geary.Imap.InternalDate : Geary.RFC822.Date, Geary.Imap.MessageData {
    public InternalDate(string iso8601) throws ImapError {
        base (iso8601);
    }
    
    /**
     * Returns the {@link InternalDate} as a {@link Parameter}.
     */
    public Parameter to_parameter() {
        return StringParameter.get_best_for(serialize());
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
    public RFC822Header(Memory.Buffer buffer) {
        base (buffer);
    }
}

public class Geary.Imap.RFC822Text : Geary.RFC822.Text, Geary.Imap.MessageData {
    public RFC822Text(Memory.Buffer buffer) {
        base (buffer);
    }
}

public class Geary.Imap.RFC822Full : Geary.RFC822.Full, Geary.Imap.MessageData {
    public RFC822Full(Memory.Buffer buffer) {
        base (buffer);
    }
}

