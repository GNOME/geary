/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.2]]
 *
 * @see SelectCommand
 */
public class Geary.Imap.ExamineCommand : Command {

    public const string NAME = "examine";

    public MailboxSpecifier mailbox { get; private set; }

    public ExamineCommand(MailboxSpecifier mailbox,
                          GLib.Cancellable? should_send) {
        base(NAME, null, should_send);
        this.mailbox = mailbox;
        this.args.add(mailbox.to_parameter());
    }

}
