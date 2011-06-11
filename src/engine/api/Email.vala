/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailHeader : Object {
    public int msg_num { get; private set; }
    public Geary.RFC822.MailboxAddresses from { get; private set; }
    public Geary.RFC822.Subject subject { get; private set; }
    public Geary.RFC822.Date sent { get; private set; }
    
    public EmailHeader(int msg_num, Geary.RFC822.MailboxAddresses from, Geary.RFC822.Subject subject,
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

public class Geary.Email : Object {
    public EmailHeader header { get; private set; }
    public string full { get; private set; }
    
    public Email(EmailHeader header, string full) {
        this.header = header;
        this.full = full;
    }
    
    /**
     * This does not return the full body or any portion of it.  It's intended only for debugging.
     */
    public string to_string() {
        return "%s (%d bytes)".printf(header.to_string(), full.data.length);
    }
}

