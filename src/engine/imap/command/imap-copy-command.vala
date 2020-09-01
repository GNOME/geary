/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.7]]
 */
public class Geary.Imap.CopyCommand : Command {

    public const string NAME = "copy";
    public const string UID_NAME = "uid copy";

    public CopyCommand(MessageSet message_set,
                       MailboxSpecifier destination,
                       GLib.Cancellable? should_send) {
        base(message_set.is_uid ? UID_NAME : NAME, null, should_send);

        this.args.add(message_set.to_parameter());
        this.args.add(destination.to_parameter());
    }
}
