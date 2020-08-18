/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An Email represents a single RFC 822 style email message.
 *
 * This class provides a common abstraction over different
 * representations of email messages, allowing messages from different
 * mail systems, from both local and remote sources, and locally
 * composed email messages to all be represented by a single
 * object. While this object represents a RFC 822 message, it also
 * holds additional metadata about an email not specified by that
 * format, such as its unique {@link id}, and unread state and other
 * {@link email_flags}.
 *
 * Email objects may by constructed in many ways, but are usually
 * obtained via a {@link Folder}. Email objects may be partial
 * representations of messages, in cases where a remote message has
 * not been fully downloaded, or a local message not fully loaded from
 * a database. This can be checked via an email's {@link fields}
 * property, and if the currently loaded fields are not sufficient,
 * then additional fields can be loaded via a folder.
 */
public class Geary.Email : BaseObject, EmailHeaderSet {

    /**
     * The maximum expected length of message body preview text.
     */
    public const int MAX_PREVIEW_BYTES = 256;

    /**
     * Indicates email fields that may change over time.
     *
     * The mutable fields are: FLAGS -- since these change as for
     * example messages are marked as read, and PREVIEW -- since the
     * preview is updated when the full message body is
     * available. All others never change once stored in the
     * database.
     */
    public const Field MUTABLE_FIELDS = (
        Geary.Email.Field.FLAGS | Geary.Email.Field.PREVIEW
    );

    /**
     * Indicates the email fields required to build an RFC822.Message.
     *
     * @see get_message
     */
    public const Field REQUIRED_FOR_MESSAGE = (
        Geary.Email.Field.HEADER | Geary.Email.Field.BODY
    );

    /**
     * Specifies specific parts of an email message.
     *
     * See the {@link Email.fields} property to determine which parts
     * an email object currently contains.
     */
    public enum Field {
        // THESE VALUES ARE PERSISTED.  Change them only if you know what you're doing.

        /** Denotes no fields. */
        NONE =              0,

        /** The RFC 822 Date header. */
        DATE =              1 << 0,

        /** The RFC 822 From, Sender, and Reply-To headers. */
        ORIGINATORS =       1 << 1,

        /** The RFC 822 To, Cc, and Bcc headers. */
        RECEIVERS =         1 << 2,

        /** The RFC 822 Message-Id, In-Reply-To, and References headers. */
        REFERENCES =        1 << 3,

        /** The RFC 822 Subject header. */
        SUBJECT =           1 << 4,

        /** The list of all RFC 822 headers. */
        HEADER =            1 << 5,

        /** The RFC 822 message body and attachments. */
        BODY =              1 << 6,

        /** The {@link Email.properties} object. */
        PROPERTIES =        1 << 7,

        /** The plain text preview. */
        PREVIEW =           1 << 8,

        /** The {@link Email.email_flags} object. */
        FLAGS =             1 << 9,

        /**
         * The union of the primary headers of a message.
         *
         * The envelope includes the {@link DATE}, {@link
         * ORIGINATORS}, {@link RECEIVERS}, {@link REFERENCES}, and
         * {@link SUBJECT} fields.
         */
        ENVELOPE = DATE | ORIGINATORS | RECEIVERS | REFERENCES | SUBJECT,

        /** The union of all email fields. */
        ALL =      DATE | ORIGINATORS | RECEIVERS | REFERENCES | SUBJECT |
                   HEADER | BODY | PROPERTIES | PREVIEW | FLAGS;

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

        public inline bool fulfills_any(Field required_fields) {
            return is_any_set(required_fields);
        }

        public inline bool require(Field required_fields) {
            return is_all_set(required_fields);
        }

        public inline bool requires_any(Field required_fields) {
            return is_any_set(required_fields);
        }

        public string to_string() {
            string value = "NONE";
            if (this == ALL) {
                value = "ALL";
            } else if (this > 0) {
                StringBuilder builder = new StringBuilder();
                foreach (Field f in all()) {
                    if (is_all_set(f)) {
                        if (!String.is_empty(builder.str)) {
                            builder.append(",");
                        }
                        builder.append(
                            ObjectUtils.to_enum_nick(typeof(Field), f).up()
                        );
                    }
                }
                value = builder.str;
            }
            return value;
        }
    }

    /**
     * A unique identifier for the Email in the Folder.
     *
     * This is is guaranteed to be unique for as long as the Folder is
     * open. Once closed, guarantees are no longer made.
     *
     * This field is always returned, no matter what Fields are used
     * to retrieve the Email.
     */
    public Geary.EmailIdentifier id { get; private set; }

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.ORIGINATORS} is set.
     */
    public RFC822.MailboxAddresses? from { get { return this._from; } }
    private RFC822.MailboxAddresses? _from  = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.ORIGINATORS} is set.
     */
    public RFC822.MailboxAddress? sender { get { return this._sender; } }
    private RFC822.MailboxAddress? _sender = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.ORIGINATORS} is set.
     */
    public RFC822.MailboxAddresses? reply_to { get { return this._reply_to; } }
    private RFC822.MailboxAddresses? _reply_to = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.RECEIVERS} is set.
     */
    public RFC822.MailboxAddresses? to { get { return this._to; } }
    private RFC822.MailboxAddresses? _to = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.RECEIVERS} is set.
     */
    public RFC822.MailboxAddresses? cc { get { return this._cc; } }
    private RFC822.MailboxAddresses? _cc = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.RECEIVERS} is set.
     */
    public RFC822.MailboxAddresses? bcc { get { return this._bcc; } }
    private RFC822.MailboxAddresses? _bcc = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.REFERENCES} is set.
     */
    public RFC822.MessageID? message_id { get { return this._message_id; } }
    private RFC822.MessageID? _message_id = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.REFERENCES} is set.
     */
    public RFC822.MessageIDList? in_reply_to { get { return this._in_reply_to; } }
    private RFC822.MessageIDList? _in_reply_to = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.REFERENCES} is set.
     */
    public RFC822.MessageIDList? references { get { return this._references; } }
    private RFC822.MessageIDList? _references = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.SUBJECT} is set.
     */
    public RFC822.Subject? subject { get { return this._subject; } }
    private RFC822.Subject? _subject = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.DATE} is set.
     */
    public RFC822.Date? date { get { return this._date; } }
    private RFC822.Date? _date = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.HEADER} is set.
     */
    public RFC822.Header? header { get; protected set; default = null; }

    /**
     * The complete RFC 822 message body.
     *
     * Value will be valid if {@link Field.BODY} is set.
     */
    public RFC822.Text? body { get; private set; default = null; }

    /**
     * MIME multipart body parts.
     *
     * Value will be valid if {@link Field.BODY} is set.
     */
    public Gee.List<Geary.Attachment> attachments { get; private set;
        default = new Gee.ArrayList<Geary.Attachment>(); }

    /**
     * A plain text prefix of the email's message body.
     *
     * Value will be valid if {@link Field.PREVIEW} is set.
     */
    public RFC822.PreviewText? preview { get; private set; default = null; }

    /**
     * Set of immutable properties for the email.
     *
     * Value will be valid if {@link Field.PROPERTIES} is set.
     */
    public Geary.EmailProperties? properties { get; private set; default = null; }

    /**
     * Set of mutable flags for the email.
     *
     * Value will be valid if {@link Field.FLAGS} is set.
     */
    public Geary.EmailFlags? email_flags { get; private set; default = null; }

    /**
     * Specifies the properties that have been populated for this email.
     *
     * Since this email object may be a partial representation of a
     * complete email message, this property lists all parts of the
     * object that have actually been loaded, as opposed to parts that
     * are simply missing from the email it represents.
     *
     * For example, if this property includes the {@link
     * Field.SUBJECT} flag, then the {@link subject} property has been
     * set to reflect the Subject header of the message. Of course,
     * the subject may then still may be null or empty, if the email
     * did not specify a subject header.
     */
    public Geary.Email.Field fields { get; private set; default = Field.NONE; }


    private Geary.RFC822.Message? message = null;


    /** Constructs a new, empty email with the given id. */
    public Email(Geary.EmailIdentifier id) {
        this.id = id;
    }

    /**
     * Construct a Geary.Email from a complete RFC822 message.
     */
    public Email.from_message(EmailIdentifier id,
                              RFC822.Message message) throws GLib.Error {
        this(id);
        set_send_date(message.date);
        set_originators(message.from, message.sender, message.reply_to);
        set_receivers(message.to, message.cc, message.bcc);
        set_full_references(
            message.message_id, message.in_reply_to, message.references
        );
        set_message_subject(message.subject);
        set_message_header(message.get_header());
        set_message_body(message.get_body());
        string preview = message.get_preview();
        if (!String.is_empty_or_whitespace(preview)) {
            set_message_preview(new RFC822.PreviewText.from_string(preview));
        }

        // Set this last as the methods above would reset it otherwise
        this.message = message;
    }

    /**
     * Determines if this message is unread from its flags.
     *
     * If {@link email_flags} is not null, returns the value of {@link
     * EmailFlags.is_unread}, otherwise returns {@link
     * Trillian.UNKNOWN}.
     */
    public inline Trillian is_unread() {
        return email_flags != null ? Trillian.from_boolean(email_flags.is_unread()) : Trillian.UNKNOWN;
    }

    /**
     * Determines if this message is flagged from its flags.
     *
     * If {@link email_flags} is not null, returns the value of {@link
     * EmailFlags.is_flagged}, otherwise returns {@link
     * Trillian.UNKNOWN}.
     */
    public inline Trillian is_flagged() {
        return email_flags != null ? Trillian.from_boolean(email_flags.is_flagged()) : Trillian.UNKNOWN;
    }

    /**
     * Determines if this message is flagged from its flags.
     *
     * If {@link email_flags} is not null, returns the value of {@link
     * EmailFlags.load_remote_images}, otherwise returns {@link
     * Trillian.UNKNOWN}.
     */
    public inline Trillian load_remote_images() {
        return email_flags != null ? Trillian.from_boolean(email_flags.load_remote_images()) : Trillian.UNKNOWN;
    }

    public void set_send_date(RFC822.Date? date) {
        this._date = date;

        this.message = null;
        this.fields |= Field.DATE;
    }

    /**
     * Sets the RFC822 originators for the message.
     *
     * RFC 2822 requires at least one From address, that the Sender
     * and From not be identical, and that both From and ReplyTo are
     * optional.
     */
    public void set_originators(RFC822.MailboxAddresses? from,
                                RFC822.MailboxAddress? sender,
                                RFC822.MailboxAddresses? reply_to)
        throws Error {
        // XXX Should be throwing an error here if from is empty or
        // sender is same as from
        this._from = from;
        this._sender = sender;
        this._reply_to = reply_to;

        this.message = null;
        this.fields |= Field.ORIGINATORS;
    }

    public void set_receivers(RFC822.MailboxAddresses? to,
                              RFC822.MailboxAddresses? cc,
                              RFC822.MailboxAddresses? bcc) {
        this._to = to;
        this._cc = cc;
        this._bcc = bcc;

        this.message = null;
        this.fields |= Field.RECEIVERS;
    }

    public void set_full_references(RFC822.MessageID? message_id,
                                    RFC822.MessageIDList? in_reply_to,
        Geary.RFC822.MessageIDList? references) {
        this._message_id = message_id;
        this._in_reply_to = in_reply_to;
        this._references = references;

        this.message = null;
        this.fields |= Field.REFERENCES;
    }

    public void set_message_subject(Geary.RFC822.Subject? subject) {
        this._subject = subject;

        this.message = null;
        this.fields |= Field.SUBJECT;
    }

    public void set_message_header(Geary.RFC822.Header header) {
        this.header = header;

        this.message = null;
        fields |= Field.HEADER;
    }

    public void set_message_body(Geary.RFC822.Text body) {
        this.body = body;

        this.message = null;
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

    public string get_searchable_attachment_list() {
        StringBuilder search = new StringBuilder();
        foreach (Geary.Attachment attachment in attachments) {
            if (attachment.has_content_filename) {
                search.append(attachment.content_filename);
                search.append("\n");
            }
        }
        return search.str;
    }

    /**
     * Constructs a new RFC 822 message from this email.
     *
     * This method requires the {@link REQUIRED_FOR_MESSAGE} fields be
     * present. If not, {@link EngineError.INCOMPLETE_MESSAGE} is
     * thrown.
     */
    public Geary.RFC822.Message get_message() throws EngineError, Error {
        if (this.message == null) {
            if (!fields.fulfills(REQUIRED_FOR_MESSAGE)) {
                throw new EngineError.INCOMPLETE_MESSAGE(
                    "Parsed email requires HEADER and BODY"
                );
            }
            this.message = new Geary.RFC822.Message.from_parts(header, body);
        }
        return this.message;
    }

    /**
     * Returns the attachment with the given MIME Content ID.
     *
     * Requires the REQUIRED_FOR_MESSAGE fields be present; else
     * EngineError.INCOMPLETE_MESSAGE is thrown.
     */
    public Geary.Attachment? get_attachment_by_content_id(string cid)
    throws EngineError {
        if (!fields.fulfills(REQUIRED_FOR_MESSAGE))
            throw new EngineError.INCOMPLETE_MESSAGE("Parsed email requires HEADER and BODY");

        foreach (Geary.Attachment attachment in attachments) {
            if (attachment.content_id == cid) {
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
        Gee.Set<RFC822.MessageID> ancestors = new Gee.HashSet<RFC822.MessageID>();

        // the email's Message-ID counts as its lineage
        if (message_id != null)
            ancestors.add(message_id);

        // References list the email trail back to its source
        if (references != null)
            ancestors.add_all(references.get_all());

        // RFC822 requires the In-Reply-To Message-ID be prepended to the References list, but
        // this ensures that's the case
        if (in_reply_to != null)
           ancestors.add_all(in_reply_to.get_all());

       return (ancestors.size > 0) ? ancestors : null;
    }

    public string get_preview_as_string() {
        return (preview != null) ? preview.buffer.to_string() : "";
    }

    public string to_string() {
        return "[%s] ".printf(id.to_string());
    }

    /**
     * Converts a Collection of {@link Email}s to a Map of Emails keyed by {@link EmailIdentifier}s.
     *
     * @return null if emails is empty or null.
     */
    public static Gee.Map<Geary.EmailIdentifier, Geary.Email>? emails_to_map(Gee.Collection<Geary.Email>? emails) {
        if (emails == null || emails.size == 0)
            return null;

        Gee.Map<Geary.EmailIdentifier, Geary.Email> map = new Gee.HashMap<Geary.EmailIdentifier,
            Geary.Email>();
        foreach (Email email in emails)
            map.set(email.id, email);

        return map;
    }

    /**
     * CompareFunc to sort {@link Email} by {@link date} ascending.
     *
     * If the date field is unavailable on either Email, their identifiers are compared to
     * stabilize the sort.
     */
    public static int compare_sent_date_ascending(Geary.Email aemail, Geary.Email bemail) {
        if (aemail.date == null || bemail.date == null) {
            GLib.message("Warning: comparing email for sent date but no Date: field loaded");

            return compare_id_ascending(aemail, bemail);
        }

        int compare = aemail.date.value.compare(bemail.date.value);

        // stabilize sort by using the mail identifier's stable sort ordering
        return (compare != 0) ? compare : compare_id_ascending(aemail, bemail);
    }

    /**
     * CompareFunc to sort {@link Email} by {@link date} descending.
     *
     * If the date field is unavailable on either Email, their identifiers are compared to
     * stabilize the sort.
     */
    public static int compare_sent_date_descending(Geary.Email aemail, Geary.Email bemail) {
        return compare_sent_date_ascending(bemail, aemail);
    }

    /**
     * CompareFunc to sort {@link Email} by {@link EmailProperties.date_received} ascending.
     *
     * If {@link properties} is unavailable on either Email, their identifiers are compared to
     * stabilize the sort.
     */
    public static int compare_recv_date_ascending(Geary.Email aemail, Geary.Email bemail) {
        if (aemail.properties == null || bemail.properties == null) {
            GLib.message("Warning: comparing email for received date but email properties not loaded");

            return compare_id_ascending(aemail, bemail);
        }

        int compare = aemail.properties.date_received.compare(bemail.properties.date_received);

        // stabilize sort with identifiers
        return (compare != 0) ? compare : compare_id_ascending(aemail, bemail);
    }

    /**
     * CompareFunc to sort {@link Email} by {@link EmailProperties.date_received} descending.
     *
     * If {@link properties} is unavailable on either Email, their identifiers are compared to
     * stabilize the sort.
     */
    public static int compare_recv_date_descending(Geary.Email aemail, Geary.Email bemail) {
        return compare_recv_date_ascending(bemail, aemail);
    }

    // only used to stabilize a sort
    private static int compare_id_ascending(Geary.Email aemail, Geary.Email bemail) {
        return aemail.id.stable_sort_comparator(bemail.id);
    }

    /**
     * CompareFunc to sort Email by EmailProperties.total_bytes.  If not available, emails are
     * compared by EmailIdentifier.
     */
    public static int compare_size_ascending(Geary.Email aemail, Geary.Email bemail) {
        Geary.EmailProperties? aprop = (Geary.EmailProperties) aemail.properties;
        Geary.EmailProperties? bprop = (Geary.EmailProperties) bemail.properties;

        if (aprop == null || bprop == null) {
            GLib.message("Warning: comparing email by size but email properties not loaded");

            return compare_id_ascending(aemail, bemail);
        }

        int cmp = (int) (aprop.total_bytes - bprop.total_bytes).clamp(-1, 1);

        return (cmp != 0) ? cmp : compare_id_ascending(aemail, bemail);
    }

    /**
     * CompareFunc to sort Email by EmailProperties.total_bytes.  If not available, emails are
     * compared by EmailIdentifier.
     */
    public static int compare_size_descending(Geary.Email aemail, Geary.Email bemail) {
        return compare_size_ascending(bemail, aemail);
    }
}

