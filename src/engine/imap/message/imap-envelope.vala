/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the IMAP ENVELOPE data.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.4.2]]
 */

public class Geary.Imap.Envelope : Geary.MessageData.AbstractMessageData, Geary.Imap.MessageData {
    public Geary.RFC822.Date? sent { get; private set; }
    public Geary.RFC822.Subject subject { get; private set; }
    public Geary.RFC822.MailboxAddresses from { get; private set; }
    public Geary.RFC822.MailboxAddresses sender { get; private set; }
    public Geary.RFC822.MailboxAddresses reply_to { get; private set; }
    public Geary.RFC822.MailboxAddresses? to { get; private set; }
    public Geary.RFC822.MailboxAddresses? cc { get; private set; }
    public Geary.RFC822.MailboxAddresses? bcc { get; private set; }
    public Geary.RFC822.MessageIDList? in_reply_to { get; private set; }
    public Geary.RFC822.MessageID? message_id { get; private set; }

    public Envelope(Geary.RFC822.Date? sent, Geary.RFC822.Subject subject,
        Geary.RFC822.MailboxAddresses from, Geary.RFC822.MailboxAddresses sender,
        Geary.RFC822.MailboxAddresses reply_to, Geary.RFC822.MailboxAddresses? to,
        Geary.RFC822.MailboxAddresses? cc, Geary.RFC822.MailboxAddresses? bcc,
        Geary.RFC822.MessageIDList? in_reply_to, Geary.RFC822.MessageID? message_id) {
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
