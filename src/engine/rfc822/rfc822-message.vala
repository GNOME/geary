/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An RFC-822 style email message.
 *
 * Unlike {@link Email}, these objects are always a complete
 * representation of an email message, and contain no information
 * other than what RFC-822 and its successor RFC documents specify.
 */
public class Geary.RFC822.Message : BaseObject, EmailHeaderSet {

    /**
     * Callback for including non-text MIME entities in message bodies.
     *
     * This delegate is an optional parameter to the body constructors
     * that allows callers to process arbitrary non-text, inline MIME
     * parts.
     *
     * This is only called for non-text MIME parts in mixed multipart
     * sections.  Inline parts referred to by rich text in alternative
     * or related documents must be located by the caller and
     * appropriately presented.
     */
    public delegate string? InlinePartReplacer(Part part);

    private const string HEADER_SENDER = "Sender";
    private const string HEADER_IN_REPLY_TO = "In-Reply-To";
    private const string HEADER_REFERENCES = "References";
    private const string HEADER_MAILER = "X-Mailer";
    private const string HEADER_BCC = "Bcc";

    // Internal note: If a header field is added here, it *must* be
    // set in stock_from_gmime().

    /** {@inheritDoc} */

    /** {@inheritDoc} */
    public RFC822.MailboxAddress? sender { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? from { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? to { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? cc { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? bcc { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MailboxAddresses? reply_to { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MessageID? message_id { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MessageIDList? in_reply_to { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.MessageIDList? references { get; protected set; default = null; }

    /** {@inheritDoc} */
    public RFC822.Subject? subject { get; protected set; default = null; }

    /** {@inheritDoc} */
    public Geary.RFC822.Date? date { get; protected set; default = null; }

    /** Value of the X-Mailer header. */
    public string? mailer { get; protected set; default = null; }

    private GMime.Message message;

    // Since GMime.Message does a bad job of separating the headers and body (GMime.Message.get_body()
    // returns the full message, headers and all), we keep a buffer around that points to the body
    // part from the source.  This is only needed by get_email().  Unfortunately, we can't always
    // set these easily, so sometimes get_email() won't work.
    private Memory.Buffer? body_buffer = null;
    private size_t? body_offset = null;


    public Message(Full full) throws RFC822Error {
        GMime.Parser parser = new GMime.Parser.with_stream(Utils.create_stream_mem(full.buffer));

        message = parser.construct_message();
        if (message == null)
            throw new RFC822Error.INVALID("Unable to parse RFC 822 message");

        // See the declaration of these fields for why we do this.
        body_buffer = full.buffer;
        body_offset = (size_t) parser.get_headers_end();

        stock_from_gmime();
    }

    public Message.from_gmime_message(GMime.Message message) {
        this.message = message;
        stock_from_gmime();
    }

    public Message.from_buffer(Memory.Buffer full_email) throws RFC822Error {
        this(new Geary.RFC822.Full(full_email));
    }

    public Message.from_parts(Header header, Text body) throws RFC822Error {
        GMime.StreamCat stream_cat = new GMime.StreamCat();
        stream_cat.add_source(new GMime.StreamMem.with_buffer(header.buffer.get_bytes().get_data()));
        stream_cat.add_source(new GMime.StreamMem.with_buffer(body.buffer.get_bytes().get_data()));

        GMime.Parser parser = new GMime.Parser.with_stream(stream_cat);
        message = parser.construct_message();
        if (message == null)
            throw new RFC822Error.INVALID("Unable to parse RFC 822 message");

        body_buffer = body.buffer;
        body_offset = 0;

        stock_from_gmime();
    }

    public Message.from_composed_email(Geary.ComposedEmail email, string? message_id) {
        this.message = new GMime.Message(true);

        // Required headers
        assert(email.from.size > 0);
        this.sender = email.sender;
        this.from = email.from;
        this.date = new RFC822.Date.from_date_time(email.date);

        // GMimeMessage.set_sender actually sets the From header - and
        // although the API docs make it sound otherwise, it also
        // supports a list of addresses
        message.set_sender(this.from.to_rfc822_string());
        message.set_date_as_string(this.date.serialize());
        if (message_id != null) {
            this.message_id = new MessageID(message_id);
            message.set_message_id(message_id);
        }

        // Optional headers
        if (email.to != null) {
            this.to = email.to;
            foreach (RFC822.MailboxAddress mailbox in email.to)
                this.message.add_recipient(GMime.RecipientType.TO, mailbox.name, mailbox.address);
        }

        if (email.cc != null) {
            this.cc = email.cc;
            foreach (RFC822.MailboxAddress mailbox in email.cc)
                this.message.add_recipient(GMime.RecipientType.CC, mailbox.name, mailbox.address);
        }

        if (email.bcc != null) {
            this.bcc = email.bcc;
            foreach (RFC822.MailboxAddress mailbox in email.bcc)
                this.message.add_recipient(GMime.RecipientType.BCC, mailbox.name, mailbox.address);
        }

        if (email.sender != null) {
            this.sender = email.sender;
            this.message.set_header(HEADER_SENDER, email.sender.to_rfc822_string());
        }

        if (email.reply_to != null) {
            this.reply_to = email.reply_to;
            this.message.set_reply_to(email.reply_to.to_rfc822_string());
        }

        if (email.in_reply_to != null) {
            this.in_reply_to = new Geary.RFC822.MessageIDList.from_rfc822_string(email.in_reply_to);
            this.message.set_header(HEADER_IN_REPLY_TO, email.in_reply_to);
        }

        if (email.references != null) {
            this.references = new Geary.RFC822.MessageIDList.from_rfc822_string(email.references);
            this.message.set_header(HEADER_REFERENCES, email.references);
        }

        if (email.subject != null) {
            this.subject = new Geary.RFC822.Subject(email.subject);
            this.message.set_subject(email.subject);
        }

        // User-Agent
        if (!Geary.String.is_empty(email.mailer)) {
            this.mailer = email.mailer;
            this.message.set_header(HEADER_MAILER, email.mailer);
        }

        // Build the message's body mime parts

        Gee.List<GMime.Object> body_parts = new Gee.LinkedList<GMime.Object>();

        // Share the body charset and encoding between plain and HTML
        // parts, so we don't need to work it out twice.
        string? body_charset = null;
        GMime.ContentEncoding? body_encoding = null;

        // Body: text format (optional)
        if (email.body_text != null) {
            GMime.Part? body_text = body_data_to_part(email.body_text.data,
                                                      ref body_charset,
                                                      ref body_encoding,
                                                      "text/plain",
                                                      true);
            body_parts.add(body_text);
        }

        // Body: HTML format (also optional)
        if (email.body_html != null) {
            const string CID_URL_PREFIX = "cid:";
            Gee.List<GMime.Object> related_parts =
                new Gee.LinkedList<GMime.Object>();

            // The files that need to have Content IDs assigned
            Gee.Map<string,File> inline_files = new Gee.HashMap<string,File>();
            inline_files.set_all(email.inline_files);

            // Create parts for inline images, if any, and updating
            // the IMG SRC attributes as we go. An inline file is only
            // included if it is actually referenced by the HTML - it
            // may have been deleted by the user after being added.

            // First, treat parts that already have Content Ids
            // assigned
            foreach (string cid in email.cid_files.keys) {
                if (email.contains_inline_img_src(CID_URL_PREFIX + cid)) {
                    File file = email.cid_files[cid];
                    GMime.Object? inline_part = get_file_part(
                        file, Geary.Mime.DispositionType.INLINE
                    );
                    if (inline_part != null) {
                        inline_part.set_content_id(cid);
                        related_parts.add(inline_part);
                    }
                    // Don't need to assign a CID to this file, so
                    // don't process it below any further.
                    inline_files.unset(cid);
                }
            }

            // Then, treat parts that need to have Content Id
            // assigned.
            if (!inline_files.is_empty) {
                const string CID_TEMPLATE = "inline_%02u@geary";
                uint cid_index = 0;
                foreach (string name in inline_files.keys) {
                    string cid = "";
                    do {
                        cid = CID_TEMPLATE.printf(cid_index++);
                    } while (email.cid_files.has_key(cid));

                    if (email.replace_inline_img_src(name,
                                                     CID_URL_PREFIX + cid)) {
                        GMime.Object? inline_part = get_file_part(
                            inline_files[name], Geary.Mime.DispositionType.INLINE
                        );
                        if (inline_part != null) {
                            inline_part.set_content_id(cid);
                            related_parts.add(inline_part);
                        }
                    }
                }
            }

            GMime.Object? body_html = body_data_to_part(email.body_html.data,
                                                        ref body_charset,
                                                        ref body_encoding,
                                                        "text/html",
                                                        false);

            // Assemble the HTML and inline images into a related
            // part, if needed
            if (!related_parts.is_empty) {
                related_parts.insert(0, body_html);
                GMime.Object? related_part =
                   coalesce_related(related_parts, "text/html");
                if (related_part != null)
                    body_html = related_part;
            }

            body_parts.add(body_html);
        }

        // Build the message's main part.
        Gee.List<GMime.Object> main_parts = new Gee.LinkedList<GMime.Object>();
        GMime.Object? body_part = coalesce_parts(body_parts, "alternative");
        if (body_part != null)
            main_parts.add(body_part);

        Gee.List<GMime.Object> attachment_parts = new Gee.LinkedList<GMime.Object>();
        foreach (File file in email.attached_files) {
            GMime.Object? attachment_part = get_file_part(
                file, Geary.Mime.DispositionType.ATTACHMENT
            );
            if (attachment_part != null)
                attachment_parts.add(attachment_part);
        }
        GMime.Object? attachment_part = coalesce_parts(attachment_parts, "mixed");
        if (attachment_part != null)
            main_parts.add(attachment_part);

        GMime.Object? main_part = coalesce_parts(main_parts, "mixed");
        this.message.set_mime_part(main_part);
    }

    // Makes a copy of the given message without the BCC fields. This is used for sending the email
    // without sending the BCC headers to all recipients.
    public Message.without_bcc(Message email) {
        // GMime doesn't make it easy to get a copy of the body of a message.  It's easy to
        // make a new message and add in all the headers, but calling set_mime_part() with
        // the existing one's get_mime_part() result yields a double Content-Type header in
        // the *original* message.  Clearly the objects aren't meant to be used like that.
        // Barring any better way to clone a message, which I couldn't find by looking at
        // the docs, we just dump out the old message to a buffer and read it back in to
        // create the new object.  Kinda sucks, but our hands are tied.
        try {
            this.from_buffer (email.message_to_memory_buffer(false, false));
        } catch (Error e) {
            error("Error creating a memory buffer from a message: %s", e.message);
        }

        // GMime also drops the ball for the *new* message.  When it comes out of the GMime
        // Parser, its "mime part" somehow isn't realizing it has a Content-Type header
        // already, so whenever you manipulate the headers, it adds a duplicate one.  This
        // odd looking hack ensures that any header manipulation is done while the "mime
        // part" is an empty object, and when we re-set the "mime part", there's only the
        // one Content-Type header.  In other words, this hack prevents the duplicate
        // header, somehow.
        GMime.Object original_mime_part = message.get_mime_part();
        GMime.Message empty = new GMime.Message(true);
        message.set_mime_part(empty.get_mime_part());

        message.remove_header(HEADER_BCC);
        bcc = null;

        message.set_mime_part(original_mime_part);
    }

    private GMime.Object? coalesce_related(Gee.List<GMime.Object> parts,
                                           string type) {
        GMime.Object? part = coalesce_parts(parts, "related");
        if (parts.size > 1) {
            part.set_header("Type", type);
        }
        return part;
    }

    private GMime.Object? coalesce_parts(Gee.List<GMime.Object> parts, string subtype) {
        if (parts.size == 0) {
            return null;
        } else if (parts.size == 1) {
            return parts.first();
        } else {
            GMime.Multipart multipart = new GMime.Multipart.with_subtype(subtype);
            foreach (GMime.Object part in parts)
                multipart.add(part);
            return multipart;
        }
    }

    private GMime.Part? get_file_part(File file,
                                      Geary.Mime.DispositionType disposition) {
        if (!file.query_exists())
            return null;

        FileInfo file_info;
        try {
            file_info = file.query_info(FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
        } catch (Error err) {
            debug("Error querying info from file: %s", err.message);
            return null;
        }

        GMime.Part part = new GMime.Part();
        part.set_disposition(disposition.serialize());
        part.set_filename(file.get_basename());
        part.set_content_type(new GMime.ContentType.from_string(file_info.get_content_type()));

        // This encoding is the initial encoding of the stream.
        GMime.StreamGIO stream = new GMime.StreamGIO(file);
        stream.set_owner(false);
        part.set_content_object(new GMime.DataWrapper.with_stream(stream, GMime.ContentEncoding.BINARY));
        part.set_content_encoding(Geary.RFC822.Utils.get_best_encoding(stream));
        return part;
    }

    /**
     * Construct a Geary.Email from a Message.  NOTE: this requires you to have created
     * the Message in such a way that its body_buffer and body_offset fields will be filled
     * out.  See the various constructors for details.  (Otherwise, we don't have a way
     * to get the body part directly, because of GMime's shortcomings.)
     */
    public Geary.Email get_email(Geary.EmailIdentifier id) throws Error {
        assert(body_buffer != null);
        assert(body_offset != null);

        Geary.Email email = new Geary.Email(id);

        email.set_message_header(new Geary.RFC822.Header(new Geary.Memory.StringBuffer(
            message.get_headers())));
        email.set_send_date(date);
        email.set_originators(from, sender, reply_to);
        email.set_receivers(to, cc, bcc);
        email.set_full_references(message_id, in_reply_to, references);
        email.set_message_subject(subject);
        email.set_message_body(new Geary.RFC822.Text(new Geary.Memory.OffsetBuffer(
            body_buffer, body_offset)));
        return email;
    }

    /**
     * Generates a preview from the email's message body.
     *
     * If there is no body, the empty string will be returned.
     */
    public string get_preview() {
        TextFormat format = TextFormat.PLAIN;
        string? preview = null;
        try {
            preview = get_plain_body(false, null);
        } catch (Error e) {
            try {
                format = TextFormat.HTML;
                preview = get_html_body(null);
            } catch (Error error) {
                debug("Could not generate message preview: %s\n and: %s",
                      e.message, error.message);
            }
        }

        return (preview != null)
            ? Geary.RFC822.Utils.to_preview_text(preview, format)
            : "";
    }

    public Gee.List<RFC822.MailboxAddress>? get_recipients() {
        Gee.List<RFC822.MailboxAddress> addrs = new Gee.ArrayList<RFC822.MailboxAddress>();

        if (to != null)
            addrs.add_all(to.get_all());

        if (cc != null)
            addrs.add_all(cc.get_all());

        if (bcc != null)
            addrs.add_all(bcc.get_all());

        return (addrs.size > 0) ? addrs : null;
    }

    /**
     * Returns the {@link Message} as a {@link Memory.Buffer} suitable for in-memory use (i.e.
     * with native linefeed characters).
     */
    public Memory.Buffer get_native_buffer() throws RFC822Error {
        return message_to_memory_buffer(false, false);
    }

    /**
     * Returns the {@link Message} as a {@link Memory.Buffer} suitable for transmission or
     * storage (i.e. using protocol-specific linefeeds).
     *
     * The buffer can also be dot-stuffed if required.  See
     * [[http://tools.ietf.org/html/rfc2821#section-4.5.2]]
     */
    public Memory.Buffer get_network_buffer(bool dotstuffed) throws RFC822Error {
        return message_to_memory_buffer(true, dotstuffed);
    }

    /**
     * Determines if the message has one or display HTML parts.
     */
    public bool has_html_body() {
        return has_body_parts(message.get_mime_part(), "html");
    }

    /**
     * Determines if the message has one or plain text display parts.
     */
    public bool has_plain_body() {
        return has_body_parts(message.get_mime_part(), "plain");
    }

    /**
     * Determines if the message has any body text/subtype MIME parts.
     *
     * A body part is one that would be displayed to the user,
     * i.e. parts returned by {@link get_html_body} or {@link
     * get_plain_body}.
     *
     * The logic for selecting text nodes here must match that in
     * construct_body_from_mime_parts.
     */
    private bool has_body_parts(GMime.Object node, string text_subtype) {
        Part part = new Part(node);
        bool is_matching_part = false;

        if (node is GMime.Multipart) {
            GMime.Multipart multipart = (GMime.Multipart) node;
            int count = multipart.get_count();
            for (int i = 0; i < count && !is_matching_part; i++) {
                is_matching_part = has_body_parts(
                    multipart.get_part(i), text_subtype
                );
            }
        } else if (node is GMime.Part) {
            Mime.DispositionType disposition = Mime.DispositionType.UNSPECIFIED;
            if (part.content_disposition != null) {
                disposition = part.content_disposition.disposition_type;
            }

            is_matching_part = (
                disposition != Mime.DispositionType.ATTACHMENT &&
                part.get_effective_content_type().is_type("text", text_subtype)
            );
        }
        return is_matching_part;
    }

    /**
     * This method is the main utility method used by the other body-generating constructors.
     *
     * Only text/* MIME parts of the specified subtype are added to body.  If a non-text part is
     * within a multipart/mixed container, the {@link InlinePartReplacer} is invoked.
     *
     * If to_html is true, the text is run through a filter to HTML-ize it.  (Obviously, this
     * should be false if text/html is being searched for.).
     *
     * The final constructed body is stored in the body string.
     *
     * The initial call should pass the root of this message and UNSPECIFIED as its container
     * subtype.
     *
     * @return Whether a text part with the desired text_subtype was found
     */
    private bool construct_body_from_mime_parts(GMime.Object node,
                                                Mime.MultipartSubtype container_subtype,
                                                string text_subtype,
                                                bool to_html,
                                                InlinePartReplacer? replacer,
                                                ref string? body)
        throws RFC822Error {
        Part part = new Part(node);
        Mime.ContentType content_type = part.get_effective_content_type();

        // If this is a multipart, call ourselves recursively on the children
        GMime.Multipart? multipart = node as GMime.Multipart;
        if (multipart != null) {
            Mime.MultipartSubtype this_subtype =
                Mime.MultipartSubtype.from_content_type(content_type, null);

            bool found_text_subtype = false;

            StringBuilder builder = new StringBuilder();
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                GMime.Object child = multipart.get_part(i);

                string? child_body = null;
                found_text_subtype |= construct_body_from_mime_parts(child, this_subtype, text_subtype,
                    to_html, replacer, ref child_body);
                if (child_body != null)
                    builder.append(child_body);
            }

            if (!String.is_empty(builder.str))
                body = builder.str;

            return found_text_subtype;
        }

        Mime.DispositionType disposition = Mime.DispositionType.UNSPECIFIED;
        if (part.content_disposition != null) {
            disposition = part.content_disposition.disposition_type;
        }

        // Process inline leaf parts
        if (node is GMime.Part &&
            disposition != Mime.DispositionType.ATTACHMENT) {

            // Assemble body from matching text parts, else use inline
            // part replacer *only* for inline parts and if in a mixed
            // multipart where each element is to be presented to the
            // user as structure dictates; For alternative and
            // related, the inline part is referred to elsewhere in
            // the document and it's the callers responsibility to
            // locate them

            if (content_type.is_type("text", text_subtype)) {
                body = part.write_to_buffer(
                    to_html ? Part.BodyFormatting.HTML : Part.BodyFormatting.NONE
                ).to_string();
            } else if (replacer != null &&
                       disposition == Mime.DispositionType.INLINE &&
                       container_subtype == Mime.MultipartSubtype.MIXED) {
                body = replacer(part);
            }
        }

        return body != null;
    }

    /**
     * A front-end to construct_body_from_mime_parts() that converts its output parameters into
     * something that front-facing methods want to return.
     */
    private string? internal_get_body(string text_subtype, bool to_html, InlinePartReplacer? replacer)
        throws RFC822Error {
        string? body = null;
        if (!construct_body_from_mime_parts(message.get_mime_part(), Mime.MultipartSubtype.UNSPECIFIED,
            text_subtype, to_html, replacer, ref body)) {
            throw new RFC822Error.NOT_FOUND("Could not find any \"text/%s\" parts", text_subtype);
        }

        return body;
    }

    /**
     * Returns the HTML portion of the message body, if present.
     *
     * Recursively walks the MIME structure (depth-first) serializing
     * all text/html MIME parts of the specified type into a single
     * UTF-8 string.  Non-text MIME parts inside of multipart/mixed
     * containers are offered to the {@link InlinePartReplacer}, which
     * can either return null or return a string that is inserted in
     * lieu of the MIME part into the final document.  All other MIME
     * parts are ignored.
     *
     * @throws RFC822Error.NOT_FOUND if an HTML body is not present.
     */
    public string? get_html_body(InlinePartReplacer? replacer) throws RFC822Error {
        return internal_get_body("html", false, replacer);
    }

    /**
     * Returns the plaintext portion of the message body, if present.
     *
     * Recursively walks the MIME structure (depth-first) serializing
     * all text/plain MIME parts of the specified type into a single
     * UTF-8 string.  Non-text MIME parts inside of multipart/mixed
     * containers are offered to the {@link InlinePartReplacer}, which
     * can either return null or return a string that is inserted in
     * lieu of the MIME part into the final document.  All other MIME
     * parts are ignored.
     *
     * The convert_to_html flag indicates if the plaintext body should
     * be converted into HTML.  Note that the InlinePartReplacer's
     * output is not converted; it's up to the caller to know what
     * format to return when invoked.
     *
     * @throws RFC822Error.NOT_FOUND if a plaintext body is not present.
     */
    public string? get_plain_body(bool convert_to_html, InlinePartReplacer? replacer) throws RFC822Error {
        return internal_get_body("plain", convert_to_html, replacer);
    }

    /**
     * Return the body as a searchable string.  The body in this case should
     * include everything visible in the message's body in the client, which
     * would be only one body part, plus any visible attachments (which can be
     * disabled by passing false in include_sub_messages).  Note that values
     * that come out of this function are persisted.
     */
    public string? get_searchable_body(bool include_sub_messages = true) {
        string? body = null;
        bool html = false;
        try {
            body = get_html_body(null);
            html = true;
        } catch (Error e) {
            try {
                body = get_plain_body(false, null);
            } catch (Error e) {
                // Ignore.
            }
        }

        if (body != null && html)
            body = Geary.HTML.html_to_text(body);

        if (include_sub_messages) {
            foreach (Message sub_message in get_sub_messages()) {
                // We index a rough approximation of what a client would be
                // displaying for each sub-message, including the subject,
                // recipients, etc.  We can avoid attachments here because
                // they're recursively picked up in the top-level message,
                // indexed separately.
                StringBuilder sub_full = new StringBuilder();
                if (sub_message.subject != null) {
                    sub_full.append(sub_message.subject.to_searchable_string());
                    sub_full.append("\n");
                }
                if (sub_message.from != null) {
                    sub_full.append(sub_message.from.to_searchable_string());
                    sub_full.append("\n");
                }
                string? recipients = sub_message.get_searchable_recipients();
                if (recipients != null) {
                    sub_full.append(recipients);
                    sub_full.append("\n");
                }
                // Our top-level get_sub_messages() recursively parses the
                // whole MIME tree, so when we get the body for a sub-message,
                // we don't need to invoke it again.
                string? sub_body = sub_message.get_searchable_body(false);
                if (sub_body != null)
                    sub_full.append(sub_body);

                if (sub_full.len > 0) {
                    if (body == null)
                        body = "";
                    body += "\n" + sub_full.str;
                }
            }
        }

        return body;
    }

    /**
     * Return the full list of recipients (to, cc, and bcc) as a searchable
     * string.  Note that values that come out of this function are persisted.
     */
    public string? get_searchable_recipients() {
        string searchable = null;
        Gee.List<RFC822.MailboxAddress>? recipient_list = get_recipients();
        if (recipient_list != null) {
            MailboxAddresses recipients = new MailboxAddresses(recipient_list);
            searchable = recipients.to_searchable_string();
        }
        return searchable;
    }

    // UNSPECIFIED disposition means "return all Mime parts"
    internal Gee.List<Part> get_attachments(
        Mime.DispositionType disposition = Mime.DispositionType.UNSPECIFIED) throws RFC822Error {
        Gee.List<Part> attachments = new Gee.LinkedList<Part>();
        get_attachments_recursively(attachments, message.get_mime_part(), disposition);
        return attachments;
    }

    private void stock_from_gmime() {
        this.message.get_header_list().foreach((name, value) => {
                switch (name.down()) {
                case "from":
                    this.from = append_address(this.from, value);
                    break;

                case "sender":
                    try {
                        this.sender = new RFC822.MailboxAddress.from_rfc822_string(value);
                    } catch (Error err) {
                        debug("Could parse subject: %s", err.message);
                    }
                    break;

                case "reply-to":
                    this.reply_to = append_address(this.reply_to, value);
                    break;

                case "to":
                    this.to = append_address(this.to, value);
                    break;

                case "cc":
                    this.cc = append_address(this.cc, value);
                    break;

                case "bcc":
                    this.bcc = append_address(this.bcc, value);
                    break;

                case "subject":
                    this.subject = new RFC822.Subject.decode(value);
                    break;

                case "date":
                    try {
                        this.date = new Geary.RFC822.Date(value);
                    } catch (Error err) {
                        debug("Could not parse date: %s", err.message);
                    }
                    break;

                case "message-id":
                    this.message_id = new MessageID(value);
                    break;

                case "in-reply-to":
                    this.in_reply_to = append_message_id(this.in_reply_to, value);
                    break;

                case "references":
                    this.references = append_message_id(this.references, value);
                    break;

                case "x-mailer":
                    this.mailer = GMime.utils_header_decode_text(value);
                    break;

                default:
                    break;
                }
            });
    }

    private MailboxAddresses append_address(MailboxAddresses? existing,
                                            string header_value) {
        MailboxAddresses addresses = new MailboxAddresses.from_rfc822_string(header_value);
        if (existing != null) {
            addresses = existing.append(addresses);
        }
        return addresses;
    }

    private MessageIDList append_message_id(MessageIDList? existing,
                                            string header_value) {
        MessageIDList ids = new MessageIDList.from_rfc822_string(header_value);
        if (existing != null) {
            ids = existing.append(ids);
        }
        return ids;
    }

    private void get_attachments_recursively(Gee.List<Part> attachments,
                                             GMime.Object root,
                                             Mime.DispositionType requested_disposition)
        throws RFC822Error {

        if (root is GMime.Multipart) {
            GMime.Multipart multipart = (GMime.Multipart) root;
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                get_attachments_recursively(attachments, multipart.get_part(i), requested_disposition);
            }
        } else if (root is GMime.MessagePart) {
            GMime.MessagePart messagepart = (GMime.MessagePart) root;
            GMime.Message message = messagepart.get_message();
            bool is_unknown;
            Mime.DispositionType disposition = Mime.DispositionType.deserialize(root.get_disposition(),
                out is_unknown);
            if (disposition == Mime.DispositionType.UNSPECIFIED || is_unknown) {
                // This is often the case, and we'll treat these as attached
                disposition = Mime.DispositionType.ATTACHMENT;
            }

            if (requested_disposition == Mime.DispositionType.UNSPECIFIED || disposition == requested_disposition) {
                GMime.Stream stream = new GMime.StreamMem();
                message.write_to_stream(stream);
                GMime.DataWrapper data = new GMime.DataWrapper.with_stream(stream,
                    GMime.ContentEncoding.BINARY);  // Equivalent to no encoding
                GMime.Part part = new GMime.Part.with_type("message", "rfc822");
                part.set_content_object(data);
                part.set_filename((message.get_subject() ?? _("(no subject)")) + ".eml");
                attachments.add(new Part(part));
            }

            get_attachments_recursively(attachments, message.get_mime_part(),
                requested_disposition);
        } else if (root is GMime.Part) {
            Part part = new Part(root);

            Mime.DispositionType actual_disposition =
                Mime.DispositionType.UNSPECIFIED;
            if (part.content_disposition != null) {
                actual_disposition = part.content_disposition.disposition_type;
            }

            if (requested_disposition == Mime.DispositionType.UNSPECIFIED ||
                actual_disposition == requested_disposition) {

                Mime.ContentType content_type =
                    part.get_effective_content_type();

                // Skip text/plain and text/html parts that are INLINE
                // or UNSPECIFIED, as they will be included in the body
                if (actual_disposition == Mime.DispositionType.ATTACHMENT ||
                    (!content_type.is_type("text", "plain") &&
                     !content_type.is_type("text", "html"))) {
                    attachments.add(part);
                }
            }
        }
    }

    public Gee.List<Geary.RFC822.Message> get_sub_messages() {
        Gee.List<Geary.RFC822.Message> messages = new Gee.ArrayList<Geary.RFC822.Message>();
        find_sub_messages(messages, message.get_mime_part());
        return messages;
    }

    private void find_sub_messages(Gee.List<Geary.RFC822.Message> messages, GMime.Object root) {
        // If this is a multipart container, check each of its children.
        GMime.Multipart? multipart = root as GMime.Multipart;
        if (multipart != null) {
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                find_sub_messages(messages, multipart.get_part(i));
            }
            return;
        }

        GMime.MessagePart? messagepart = root as GMime.MessagePart;
        if (messagepart != null) {
            GMime.Message sub_message = messagepart.get_message();
            if (sub_message != null) {
                messages.add(new Geary.RFC822.Message.from_gmime_message(sub_message));
            } else {
                warning("Corrupt message, possibly bug 769697");
            }
        }
    }

    private Memory.Buffer message_to_memory_buffer(bool encoded, bool dotstuffed) throws RFC822Error {
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);

        GMime.StreamFilter stream_filter = new GMime.StreamFilter(stream);
        stream_filter.add(new GMime.FilterCRLF(encoded, dotstuffed));

        if (message.write_to_stream(stream_filter) < 0)
            throw new RFC822Error.FAILED("Unable to write RFC822 message to memory buffer");

        if (stream_filter.flush() != 0)
            throw new RFC822Error.FAILED("Unable to flush RFC822 message to memory buffer");

        return new Memory.ByteBuffer.from_byte_array(byte_array);
    }

    public string to_string() {
        return message.to_string();
    }

    /**
     * Returns a MIME part for some body content.
     *
     * Determining the appropriate body charset and encoding is
     * unfortunately a multi-step process that involves reading it
     * completely, several times:
     *
     * 1. Guess the best charset by scanning the complete body.
     * 2. Convert the body into the preferred charset, essential
     *    to avoid e.g. guessing Base64 encoding for ISO-8859-1
     *    because of the 0x0's present in UTF bytes with high-bit
     *    chars.
     * 3. Determine, given the correctly encoded charset
     *    what the appropriate encoding is by scanning the
     *    complete, encoded body.
     *
     * This applies to both text/plain and text/html parts, but we
     * don't need to do it repeatedly for each, since HTML is 7-bit
     * clean ASCII. So if we have guessed both already for a plain
     * text body, it will still apply for any HTML part.
     */
    private GMime.Part body_data_to_part(uint8[] content,
                                         ref string? charset,
                                         ref GMime.ContentEncoding? encoding,
                                         string content_type,
                                         bool is_flowed) {
        GMime.Stream content_stream = new GMime.StreamMem.with_buffer(content);
        if (charset == null) {
            charset = Geary.RFC822.Utils.get_best_charset(content_stream);
        }
        GMime.StreamFilter filter_stream = new GMime.StreamFilter(content_stream);
        filter_stream.add(new GMime.FilterCharset(UTF8_CHARSET, charset));
        if (encoding == null) {
            encoding = Geary.RFC822.Utils.get_best_encoding(filter_stream);
        }
        if (is_flowed && encoding == GMime.ContentEncoding.BASE64) {
            // Base64-encoded text needs to have CR's added after LF's
            // before encoding, otherwise it breaks format=flowed. See
            // Bug 753528.
            filter_stream.add(new GMime.FilterCRLF(true, false));
        }

        GMime.ContentType complete_type =
            new GMime.ContentType.from_string(content_type);
        complete_type.set_parameter("charset", charset);
        if (is_flowed) {
            complete_type.set_parameter("format", "flowed");
        }

        GMime.DataWrapper body = new GMime.DataWrapper.with_stream(
            filter_stream, GMime.ContentEncoding.DEFAULT
        );

        GMime.Part body_part = new GMime.Part();
        body_part.set_content_type(complete_type);
        body_part.set_content_object(body);
        body_part.set_content_encoding(encoding);
        return body_part;
    }

}
