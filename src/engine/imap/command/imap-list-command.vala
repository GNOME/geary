/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.3.8]]
 *
 * @see MailboxInformation
 */

public class Geary.Imap.ListCommand : Command {
    public const string NAME = "list";
    public const string XLIST_NAME = "xlist";
    
    public ListCommand(MailboxSpecifier mailbox, bool use_xlist) {
        base (use_xlist ? XLIST_NAME : NAME, { "" });
        
        add(mailbox.to_parameter());
    }
    
    public ListCommand.wildcarded(string reference, MailboxSpecifier mailbox, bool use_xlist) {
        base (use_xlist ? XLIST_NAME : NAME, { reference });
        
        add(mailbox.to_parameter());
    }
}

