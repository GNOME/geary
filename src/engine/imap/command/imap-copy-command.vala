/* Copyright 2011-2013 Yorba Foundation
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

    public CopyCommand(MessageSet message_set, MailboxSpecifier destination) {
        base (message_set.is_uid ? UID_NAME : NAME);

        add(message_set.to_parameter());
        add(destination.to_parameter());
    }
}

