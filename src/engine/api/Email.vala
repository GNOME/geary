/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Email : Object {
    [Flags]
    public enum Field {
        NONE = 0,
        DATE,
        ORIGINATORS,
        RECEIVERS,
        REFERENCES,
        SUBJECT,
        HEADER,
        BODY,
        PROPERTIES,
        ENVELOPE = DATE | ORIGINATORS | RECEIVERS | REFERENCES | SUBJECT,
        ALL = 0xFFFFFFFF;
        
        public static Field[] all() {
            return {
                DATE,
                ORIGINATORS,
                RECEIVERS,
                REFERENCES,
                SUBJECT,
                HEADER,
                BODY,
                PROPERTIES
            };
        }
    }
    
    public Geary.EmailLocation location { get; private set; }
    
    // DATE
    public Geary.RFC822.Date? date = null;
    
    // ORIGINATORS
    public Geary.RFC822.MailboxAddresses? from = null;
    public Geary.RFC822.MailboxAddresses? sender = null;
    public Geary.RFC822.MailboxAddresses? reply_to = null;
    
    // RECEIVERS
    public Geary.RFC822.MailboxAddresses? to = null;
    public Geary.RFC822.MailboxAddresses? cc = null;
    public Geary.RFC822.MailboxAddresses? bcc = null;
    
    // REFERENCES
    public Geary.RFC822.MessageID? message_id = null;
    public Geary.RFC822.MessageID? in_reply_to = null;
    
    // SUBJECT
    public Geary.RFC822.Subject? subject = null;
    
    // HEADER
    public RFC822.Header? header = null;
    
    // BODY
    public RFC822.Text? body = null;
    
    // PROPERTIES
    public Geary.EmailProperties? properties = null;
    
    public Email(Geary.EmailLocation location) {
        this.location = location;
    }
    
    public string to_string() {
        StringBuilder builder = new StringBuilder();
        
        if (date != null)
            builder.append_printf("[%s]", date.to_string());
        
        if (from != null)
            builder.append_printf("[From: %s]", from.to_string());
        
        if (to != null)
            builder.append_printf("[To: %s]", to.to_string());
        
        if (subject != null)
            builder.append_printf("[Subj: %s]", subject.to_string());
        
        if (header != null)
            builder.append_printf("[Header: %lub]", header.buffer.get_size());
        
        if (body != null)
            builder.append_printf("[Body: %lub]", body.buffer.get_size());
        
        return builder.str;
    }
}

