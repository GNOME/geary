/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Denotes an object that has a set of RFC822 headers.
 */
public interface Geary.EmailHeaderSet : BaseObject {

    /** Value of the RFC 822 Date header. */
    public abstract RFC822.Date? date { get; protected set; }

    /** Value of the RFC 822 From header, an originator field. */
    public abstract RFC822.MailboxAddresses? from { get; protected set; }

    /** Value of the RFC 822 Sender header, an originator field. */
    public abstract RFC822.MailboxAddress? sender { get; protected set; }

    /** Value of the RFC 822 Reply-To header, an originator field. */
    public abstract RFC822.MailboxAddresses? reply_to { get; protected set; }

    /** Value of the RFC 822 To header, a recipient field. */
    public abstract RFC822.MailboxAddresses? to { get; protected set; }

    /** Value of the RFC 822 Cc header, a recipient field. */
    public abstract RFC822.MailboxAddresses? cc { get; protected set; }

    /** Value of the RFC 822 Bcc header, a recipient field. */
    public abstract RFC822.MailboxAddresses? bcc { get; protected set; }

    /** Value of the RFC 822 Message-Id header, a reference field. */
    public abstract RFC822.MessageID? message_id { get; protected set; }

    /** Value of the RFC 822 In-Reply-To header, a reference field. */
    public abstract RFC822.MessageIDList? in_reply_to { get; protected set; }

    /** Value of the RFC 822 References header, a reference field. */
    public abstract RFC822.MessageIDList? references { get; protected set; }

    /** Value of the RFC 822 Subject header. */
    public abstract RFC822.Subject? subject { get; protected set; }

}
