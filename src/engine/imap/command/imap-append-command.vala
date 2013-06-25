/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the IMAP APPEND command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.11]]
 */

public class Geary.Imap.AppendCommand : Command {
    public const string NAME = "append";
    
    public AppendCommand(MailboxSpecifier mailbox, MessageFlags? flags, InternalDate? internal_date,
        Memory.Buffer message) {
        base (NAME);
        
        add(mailbox.to_parameter());
        
        if (flags != null && flags.size > 0)
            add(flags.to_parameter());
        
        if (internal_date != null)
            add(internal_date.to_parameter());
        
        add(new LiteralParameter(message));
    }
}

