/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Message {
    public int msg_num { get; private set; }
    public Geary.RFC822.MailboxAddresses from { get; private set; }
    public Geary.RFC822.Subject subject { get; private set; }
    public Geary.RFC822.Date sent { get; private set; }
    
    public Message(int msg_num, Geary.RFC822.MailboxAddresses from, Geary.RFC822.Subject subject,
        Geary.RFC822.Date sent) {
        this.msg_num = msg_num;
        this.from = from;
        this.subject = subject;
        this.sent = sent;
    }
    
    public string to_string() {
        return "[%d] %s: %s (%s)".printf(msg_num, from.to_string(), subject.to_string(), sent.to_string());
    }
}

