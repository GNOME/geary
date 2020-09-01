/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * The RFC 3501 DELETE command.
 *
 * Deletes the given mailbox. Per the RFC, this must not be used to
 * delete mailboxes with child (inferior) mailboxes and that also are
 * marked \Noselect.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.4]]
 */
public class Geary.Imap.DeleteCommand : Command {

    public const string NAME = "DELETE";

    public DeleteCommand(MailboxSpecifier mailbox,
                         GLib.Cancellable? should_send) {
        base(NAME, null, should_send);
        this.args.add(mailbox.to_parameter());
    }

}
