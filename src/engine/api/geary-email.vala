/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Email : Object {
    // This value is not persisted, but it does represent the expected max size of the preview
    // when returned.
    public const int MAX_PREVIEW_BYTES = 128;
    
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
        PREVIEW =           1 << 8,
        
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
                PROPERTIES,
                PREVIEW
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
    
    /**
     * position is the one-based addressing of the email in the folder, in the notion that messages
     * are "stacked" from 1 to n, earliest to newest.  "Earliest" and "newest" do not necessarily
     * correspond to the emails' send or receive time, merely how they've been arranged on the stack.
     *
     * This value is only good at the time the Email is requested from the folder.  Subsequent
     * operations may change the Email's position in the folder (or simply remove it).  This value
     * is *not* updated to reflect this.
     *
     * This field is always returned, no matter what Fields are used to retrieve the Email.
     */
    public int position { get; private set; }
    
    /**
     * id is a unique identifier for the Email in the Folder.  It is guaranteed to be unique for
     * as long as the Folder is open.  Once closed, guarantees are no longer made.
     *
     * This field is always returned, no matter what Fields are used to retrieve the Email.
     */
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
    public Geary.RFC822.MessageIDList? references { get; private set; default = null; }
    
    // SUBJECT
    public Geary.RFC822.Subject? subject { get; private set; default = null; }
    
    // HEADER
    public RFC822.Header? header { get; private set; default = null; }
    
    // BODY
    public RFC822.Text? body { get; private set; default = null; }
    
    // PROPERTIES
    public Geary.EmailProperties? properties { get; private set; default = null; }
    
    // PREVIEW
    public RFC822.PreviewText? preview { get; private set; default = null; }
    
    public Geary.Email.Field fields { get; private set; default = Field.NONE; }
    
    private Geary.RFC822.Message? message = null;
    
    public Email(int position, Geary.EmailIdentifier id) {
        assert(position >= 1);
        
        this.position = position;
        this.id = id;
    }
    
    internal void update_position(int position) {
        assert(position >= 1);
        
        this.position = position;
    }

    public inline Trillian is_unread() {
        return properties == null ? Trillian.UNKNOWN :
            Trillian.from_boolean(properties.email_flags.is_unread());
    }

    public inline Trillian is_flagged() {
        return properties == null ? Trillian.UNKNOWN :
            Trillian.from_boolean(properties.email_flags.is_flagged());
    }

    public inline EmailFlags? get_flags() {
        return properties == null ? null : properties.email_flags;
    }

    public void set_flags(Geary.EmailFlags flags) {
        if (properties != null) {
            properties.email_flags = flags;
        }
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
    
    public void set_full_references(Geary.RFC822.MessageID? message_id, Geary.RFC822.MessageID? in_reply_to,
        Geary.RFC822.MessageIDList? references) {
        this.message_id = message_id;
        this.in_reply_to = in_reply_to;
        this.references = references;
        
        fields |= Field.REFERENCES;
    }
    
    public void set_message_subject(Geary.RFC822.Subject? subject) {
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
    
    public void set_message_preview(Geary.RFC822.PreviewText preview) {
        this.preview = preview;
        
        fields |= Field.PREVIEW;
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
        
        builder.append_printf("[#%d/%s] ", position, id.to_string());
        
        if (date != null)
            builder.append_printf("%s/", date.to_string());
        
        return builder.str;
    }
}

