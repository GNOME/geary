/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Email : BaseObject {
    // This value is not persisted, but it does represent the expected max size of the preview
    // when returned.
    public const int MAX_PREVIEW_BYTES = 128;
    
    /**
     * Currently only one field is mutable: FLAGS.  All others never change once stored in the
     * database.
     */
    public const Field MUTABLE_FIELDS = Geary.Email.Field.FLAGS;
    
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
        FLAGS =             1 << 9,
        
        ENVELOPE =          DATE | ORIGINATORS | RECEIVERS | REFERENCES | SUBJECT,
        ALL =               DATE | ORIGINATORS | RECEIVERS | REFERENCES | SUBJECT | HEADER | BODY
                            | PROPERTIES | PREVIEW | FLAGS;
        
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
                PREVIEW,
                FLAGS
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
        
        public string to_list_string() {
            StringBuilder builder = new StringBuilder();
            foreach (Field f in all()) {
                if (is_all_set(f)) {
                    if (!String.is_empty(builder.str))
                        builder.append(", ");
                    
                    builder.append(f.to_string());
                }
            }
            
            return builder.str;
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
    public Gee.List<Geary.Attachment> attachments { get; private set;
        default = new Gee.ArrayList<Geary.Attachment>(); }
    
    // PROPERTIES
    public Geary.EmailProperties? properties { get; private set; default = null; }
    
    // PREVIEW
    public RFC822.PreviewText? preview { get; private set; default = null; }
    
    // FLAGS
    public Geary.EmailFlags? email_flags { get; private set; default = null; }
    
    public Geary.Email.Field fields { get; private set; default = Field.NONE; }
    
    private Geary.RFC822.Message? message = null;
    
    public Email(int position, Geary.EmailIdentifier id) {
        this.position = position;
        this.id = id;
    }
    
    internal void update_position(int position) {
        assert(position >= 1);
        
        this.position = position;
    }

    public inline Trillian is_unread() {
        return email_flags != null ? Trillian.from_boolean(email_flags.is_unread()) : Trillian.UNKNOWN;
    }

    public inline Trillian is_flagged() {
        return email_flags != null ? Trillian.from_boolean(email_flags.is_flagged()) : Trillian.UNKNOWN;
    }

    public void set_send_date(Geary.RFC822.Date? date) {
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

    public void set_flags(Geary.EmailFlags email_flags) {
        this.email_flags = email_flags;
        
        fields |= Field.FLAGS;
    }

    public void add_attachment(Geary.Attachment attachment) {
        attachments.add(attachment);
    }
    
    public void add_attachments(Gee.Collection<Geary.Attachment> attachments) {
        this.attachments.add_all(attachments);
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

    public Geary.Attachment? get_attachment(int64 attachment_id) throws EngineError {
        if (!fields.fulfills(Field.HEADER | Field.BODY))
            throw new EngineError.INCOMPLETE_MESSAGE("Parsed email requires HEADER and BODY");

        foreach (Geary.Attachment attachment in attachments) {
            if (attachment.id == attachment_id) {
                return attachment;
            }
        }
        return null;
    }

    /**
     * Returns a list of this email's ancestry by Message-ID.  IDs are not returned in any
     * particular order.  The ancestry is made up from this email's Message-ID, its References,
     * and its In-Reply-To.  Thus, this email must have been fetched with Field.REFERENCES for
     * this method to return a complete list.
     */
    public Gee.Set<RFC822.MessageID>? get_ancestors() {
        Gee.Set<RFC822.MessageID> ancestors = new Gee.HashSet<RFC822.MessageID>(
            Hashable.hash_func, Equalable.equal_func);
        
        // the email's Message-ID counts as its lineage
        if (message_id != null)
            ancestors.add(message_id);
        
        // References list the email trail back to its source
        if (references != null && references.list != null)
            ancestors.add_all(references.list);
        
        // RFC822 requires the In-Reply-To Message-ID be prepended to the References list, but
        // this ensures that's the case
        if (in_reply_to != null)
           ancestors.add(in_reply_to);
       
       return (ancestors.size > 0) ? ancestors : null;
    }
    
    public string get_preview_as_string() {
        return (preview != null) ? preview.buffer.to_string() : "";
    }

    public string get_subject_as_string() {
        return (subject != null) ? subject.value : "";
    }
    
    /**
     * Returns the primary originator of an email, which is defined as the first mailbox address
     * in From:, Sender:, or Reply-To:, in that order, depending on availability.
     *
     * Returns null if no originators are present.
     */
    public RFC822.MailboxAddress? get_primary_originator() {
        if (from != null && from.size > 0)
            return from[0];
        
        if (sender != null && sender.size > 0)
            return sender[0];
        
        if (reply_to != null && reply_to.size > 0)
            return reply_to[0];
        
        return null;
    }
    
    public string to_string() {
        StringBuilder builder = new StringBuilder();
        
        builder.append_printf("[#%d/%s] ", position, id.to_string());
        
        if (date != null)
            builder.append_printf("%s/", date.to_string());
        
        return builder.str;
    }
    
    /**
     * CompareFunc to sort Email by date.  If the date field is not available on both Emails, their
     * identifiers are compared.
     */
    public static int compare_date_ascending(void* a, void *b) {
        Geary.Email *aemail = (Geary.Email *) a;
        Geary.Email *bemail = (Geary.Email *) b;
        
        int diff = 0;
        if (aemail->date != null && bemail->date != null)
            diff = aemail->date.value.compare(bemail->date.value);
        
        // stabilize sort by using the mail's ordering, which is always unique in a folder
        return (diff != 0) ? diff : aemail->id.compare(bemail->id);
    }
    
    /**
     * CompareFunc to sort Email by date.  If the date field is not available on both Emails, their
     * identifiers are compared.
     */
    public static int compare_date_descending(void* a, void *b) {
        return compare_date_ascending(b, a);
    }
    
    /**
     * CompareFunc to sort Email by EmailIdentifier.
     */
    public static int compare_id_ascending(void* a, void *b) {
        return ((Email *) a)->id.compare(((Email *) b)->id);
    }
    
    /**
     * CompareFunc to sort Email by EmailIdentifier.
     */
    public static int compare_id_descending(void* a, void *b) {
        return compare_id_ascending(b, a);
    }
    
    /**
     * CompareFunc to sort Email by EmailProperties.total_bytes.  If not available, emails are
     * compared by EmailIdentifier.
     */
    public static int compare_size_ascending(void *a, void *b) {
        Geary.EmailProperties? aprop = (Geary.EmailProperties) ((Geary.Email *) a)->properties;
        Geary.EmailProperties? bprop = (Geary.EmailProperties) ((Geary.Email *) b)->properties;
        
        if (aprop == null || bprop == null)
            return compare_id_ascending(a, b);
        
        long asize = aprop.total_bytes;
        long bsize = bprop.total_bytes;
        
        if (asize < bsize)
            return -1;
        else if (asize > bsize)
            return 1;
        else
            return compare_id_ascending(a, b);
    }
    
    /**
     * CompareFunc to sort Email by EmailProperties.total_bytes.  If not available, emails are
     * compared by EmailIdentifier.
     */
    public static int compare_size_descending(void *a, void *b) {
        return compare_size_ascending(b, a);
    }
    
    /**
     * CompareFunc to sort Email by EmailProperties.date_received.  If not available, emails are
     * compared by EmailIdentifier.
     */
    public static int compare_date_received_ascending(void *a, void *b) {
        Geary.Email aemail = (Geary.Email) a;
        Geary.Email bemail = (Geary.Email) b;
        
        if (aemail.properties == null || bemail.properties == null)
            return compare_id_ascending(a, b);
        
        int cmp = aemail.properties.date_received.compare(bemail.properties.date_received);
        
        return (cmp != 0) ? cmp : compare_id_ascending(a, b);
    }
    
    /**
     * CompareFunc to sort Email by EmailProperties.date_received.  If not available, emails are
     * compared by EmailIdentifier.
     */
    public static int compare_date_received_descending(void *a, void *b) {
        return compare_date_received_ascending(b, a);
    }
}

