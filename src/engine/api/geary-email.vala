/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Email : Object {
    // THESE VALUES ARE PERSISTED.  Change them only if you know what you're doing.
    public enum Field {
        NONE =              0,
        DATE =              1 << 0,
        ORIGINATORS =       1 << 1,
        RECEIVERS =         1 << 2,
        REFERENCES =        1 << 3,
        SUBJECT =           1 << 4,
        HEADER =            1 << 5,
        BODY =              1 << 6,
        PROPERTIES =        1 << 7,
        ENVELOPE =          DATE | ORIGINATORS | RECEIVERS | REFERENCES | SUBJECT,
        ALL =               0xFFFFFFFF;
        
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
        
        public inline bool is_all_set(Field required_fields) {
            return (this & required_fields) == required_fields;
        }
        
        public inline bool is_any_set(Field required_fields) {
            return (this & required_fields) != 0;
        }
        
        public inline Field set(Field field) {
            return (this | field);
        }
        
        public inline Field clear(Field field) {
            return (this & ~(field));
        }
        
        public inline bool fulfills(Field required_fields) {
            return is_all_set(required_fields);
        }
        
        public inline bool require(Field required_fields) {
            return is_all_set(required_fields);
        }
    }
    
    public Geary.EmailLocation location { get; private set; }
    public Geary.EmailIdentifier id { get; private set; }
    
    // DATE
    public Geary.RFC822.Date? date { get; private set; default = null; }
    
    // ORIGINATORS
    public Geary.RFC822.MailboxAddresses? from { get; private set; default = null; }
    public Geary.RFC822.MailboxAddresses? sender { get; private set; default = null; }
    public Geary.RFC822.MailboxAddresses? reply_to { get; private set; default = null; }
    
    // RECEIVERS
    public Geary.RFC822.MailboxAddresses? to { get; private set; default = null; }
    public Geary.RFC822.MailboxAddresses? cc { get; private set; default = null; }
    public Geary.RFC822.MailboxAddresses? bcc { get; private set; default = null; }
    
    // REFERENCES
    public Geary.RFC822.MessageID? message_id { get; private set; default = null; }
    public Geary.RFC822.MessageID? in_reply_to { get; private set; default = null; }
    
    // SUBJECT
    public Geary.RFC822.Subject? subject { get; private set; default = null; }
    
    // HEADER
    public RFC822.Header? header { get; private set; default = null; }
    
    // BODY
    public RFC822.Text? body { get; private set; default = null; }
    
    // PROPERTIES
    public Geary.EmailProperties? properties { get; private set; default = null; }
    
    public Geary.Email.Field fields { get; private set; default = Field.NONE; }
    
    private Geary.RFC822.Message? message = null;
    
    public Email(Geary.EmailLocation location, Geary.EmailIdentifier id) {
        this.location = location;
        this.id = id;
    }
    
    public void update_location(Geary.EmailLocation location) {
        this.location = location;
    }
    
    public void set_send_date(Geary.RFC822.Date date) {
        this.date = date;
        
        fields |= Field.DATE;
    }
    
    public void set_originators(Geary.RFC822.MailboxAddresses? from,
        Geary.RFC822.MailboxAddresses? sender, Geary.RFC822.MailboxAddresses? reply_to) {
        this.from = from;
        this.sender = sender;
        this.reply_to = reply_to;
        
        fields |= Field.ORIGINATORS;
    }
    
    public void set_receivers(Geary.RFC822.MailboxAddresses? to,
        Geary.RFC822.MailboxAddresses? cc, Geary.RFC822.MailboxAddresses? bcc) {
        this.to = to;
        this.cc = cc;
        this.bcc = bcc;
        
        fields |= Field.RECEIVERS;
    }
    
    public void set_references(Geary.RFC822.MessageID? message_id, Geary.RFC822.MessageID? in_reply_to) {
        this.message_id = message_id;
        this.in_reply_to = in_reply_to;
        
        fields |= Field.REFERENCES;
    }
    
    public void set_message_subject(Geary.RFC822.Subject subject) {
        this.subject = subject;
        
        fields |= Field.SUBJECT;
    }
    
    public void set_message_header(Geary.RFC822.Header header) {
        this.header = header;
        
        // reset the message object, which is built from this text
        message = null;
        
        fields |= Field.HEADER;
    }
    
    public void set_message_body(Geary.RFC822.Text body) {
        this.body = body;
        
        // reset the message object, which is built from this text
        message = null;
        
        fields |= Field.BODY;
    }
    
    public void set_email_properties(Geary.EmailProperties properties) {
        this.properties = properties;
        
        fields |= Field.PROPERTIES;
    }
    
    /**
     * This method requires Geary.Email.Field.HEADER and Geary.Email.Field.BODY be present.
     * If not, EngineError.INCOMPLETE_MESSAGE is thrown.
     */
    public Geary.RFC822.Message get_message() throws EngineError, RFC822Error {
        if (message != null)
            return message;
        
        if (!fields.fulfills(Field.HEADER | Field.BODY))
            throw new EngineError.INCOMPLETE_MESSAGE("Parsed email requires HEADER and BODY");
        
        message = new Geary.RFC822.Message.from_parts(header, body);
        
        return message;
    }
    
    public string to_string() {
        StringBuilder builder = new StringBuilder();
        
        builder.append_printf("[#%d/%s] ", location.position, id.to_string());
        
        if (date != null)
            builder.append_printf("[%s]", date.to_string());
        
        return builder.str;
    }
}

