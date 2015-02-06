/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.3]]
 */

public class Geary.Imap.CreateCommand : Command {
    public const string NAME = "create";
    
    public MailboxSpecifier mailbox { get; private set; }
    
    public CreateCommand(MailboxSpecifier mailbox) {
        base (NAME);
        
        this.mailbox = mailbox;
        
        add(mailbox.to_parameter());
    }
}
