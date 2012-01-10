/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.ComposedEmail : Object {
    public DateTime date { get; set; }
    public RFC822.MailboxAddresses from { get; set; }
    public RFC822.MailboxAddresses? to { get; set; default = null; }
    public RFC822.MailboxAddresses? cc { get; set; default = null; }
    public RFC822.MailboxAddresses? bcc { get; set; default = null; }
    public RFC822.Subject? subject { get; set; default = null; }
    public RFC822.Text? body { get; set; default = null; }
    
    public ComposedEmail(DateTime date, RFC822.MailboxAddresses from) {
        this.date = date;
        this.from = from;
    }
}

