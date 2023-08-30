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


    private const string HEADER_IN_REPLY_TO = "In-Reply-To";
    private const string HEADER_REFERENCES = "References";
    private const string HEADER_MAILER = "X-Mailer";
    private const string HEADER_BCC = "Bcc";
    private const string[] HEADER_AUTH_RESULTS = {
        "ARC-Authentication-Results",
        "Authentication-Results",
        "X-Original-Authentication-Results"
    };

    /** Options to use when serialising a message in RFC 822 format. */
    [Flags]
    public enum RFC822FormatOptions {

        /** Format for RFC 822 in general. */
        NONE,

        /**
         * The message should be serialised for transmission via SMTP.
         *
         * SMTP imposes both operational and data-format requirements
         * on RFC 822 style messages. In particular, BCC headers
         * should not be included since they will expose BCC
         * recipients, and lines must be dot-stuffed so as to avoid
         * terminating the message early if a line starting with a `.`
         * is encountered.
         *
         * See [[http://tools.ietf.org/html/rfc5321#section-4.5.2]]
         */
        SMTP_FORMAT;

    }


    // Internal note: If a header field is added here, it *must* be
    // set in Message.from_gmime_message(), below.

    /** {@inheritDoc} */
    public MailboxAddresses? from { get { return this._from; } }
    private MailboxAddresses? _from  = null;

    /** {@inheritDoc} */
    public MailboxAddress? sender { get { return this._sender; } }
    private MailboxAddress? _sender = null;

    /** {@inheritDoc} */
    public MailboxAddresses? reply_to { get { return this._reply_to; } }
    private MailboxAddresses? _reply_to = null;

    /** {@inheritDoc} */
    public MailboxAddresses? to { get { return this._to; } }
    private MailboxAddresses? _to = null;

    /** {@inheritDoc} */
    public MailboxAddresses? cc { get { return this._cc; } }
    private MailboxAddresses? _cc = null;

    /** {@inheritDoc} */
    public MailboxAddresses? bcc { get { return this._bcc; } }
    private MailboxAddresses? _bcc = null;

    /** {@inheritDoc} */
    public MessageID? message_id { get { return this._message_id; } }
    private MessageID? _message_id = null;

    /** {@inheritDoc} */
    public MessageIDList? in_reply_to { get { return this._in_reply_to; } }
    private MessageIDList? _in_reply_to = null;

    /** {@inheritDoc} */
    public MessageIDList? references { get { return this._references; } }
    private MessageIDList? _references = null;

    /** {@inheritDoc} */
    public Subject? subject { get { return this._subject; } }
    private Subject? _subject = null;

    /** {@inheritDoc} */
    public Date? date { get { return this._date; } }
    private Date? _date = null;

    /**
     * {@inheritDoc}
     *
     * Value will be valid if {@link Field.AUTH_RESULTS} is set.
     */
    public RFC822.AuthenticationResults? auth_results { get { return this._auth_results; } }
    private RFC822.AuthenticationResults? _auth_results = null;

    /** Value of the X-Mailer header. */
    public string? mailer { get; protected set; default = null; }

    // The backing store for this message. Used to access body parts.
    private GMime.Message message;


    public Message(Full full) throws Error {
        GMime.Parser parser = new GMime.Parser.with_stream(
            Utils.create_stream_mem(full.buffer)
        );
        var message = parser.construct_message(get_parser_options());
        if (message == null) {
            throw new Error.INVALID("Unable to parse RFC 822 message");
        }

        this.from_gmime_message(message);
    }

    public Message.from_gmime_message(GMime.Message message)
        throws Error {
        this.message = message;

        this._from = to_addresses(message.get_from());
        this._to = to_addresses(message.get_to());
        this._cc = to_addresses(message.get_cc());
        this._bcc = to_addresses(message.get_bcc());
        this._reply_to = to_addresses(message.get_reply_to());

        var sender = (
            message.get_sender().get_address(0) as GMime.InternetAddressMailbox
        );
        if (sender != null) {
            this._sender = new MailboxAddress.from_gmime(sender);
        }

        var subject = message.get_subject();
        if (subject != null) {
            this._subject = new Subject(subject);
        }

        // Use a pointer here to work around GNOME/vala#986
        GLib.DateTime* date = message.get_date();
        if (date != null) {
            this._date = new Date(date);
        }

        var message_id = message.get_message_id();
        if (message_id != null) {
            this._message_id = new MessageID(message_id);
        }

        foreach (string field in HEADER_AUTH_RESULTS) {
            var auth_results = message.get_header(field);
            if (auth_results != null) {
                this._auth_results = new AuthenticationResults(auth_results);
                break;
            }
        }

        // Since these headers may be specified multiple times, we
        // need to iterate over all of them to find them.
        var headers = message.get_header_list();
        for (int i = 0; i < headers.get_count(); i++) {
            var header = headers.get_header_at(i);
            switch (header.get_name().down()) {
            case "in-reply-to":
                this._in_reply_to = append_message_id(
                    this._in_reply_to, header.get_raw_value()
                );
                break;

            case "references":
                this._references = append_message_id(
                    this._references, header.get_raw_value()
                );
                break;

            default:
                break;
            }
        }

        this.mailer = message.get_header("X-Mailer");
    }

    public Message.from_buffer(Memory.Buffer full_email)
        throws Error {
        this(new Geary.RFC822.Full(full_email));
    }

    public Message.from_parts(Header header, Text body)
        throws Error {
        GMime.StreamCat stream_cat = new GMime.StreamCat();

        if (header.buffer.size != 0) {
            stream_cat.add_source(new GMime.StreamMem.with_buffer(header.buffer.get_bytes().get_data()));
        } else {
            throw new Error.INVALID("Missing header in RFC 822 message");
        }
        if (body.buffer.size != 0) {
            stream_cat.add_source(new GMime.StreamMem.with_buffer(body.buffer.get_bytes().get_data()));
        }

        GMime.Parser parser = new GMime.Parser.with_stream(stream_cat);
        var message = parser.construct_message(Geary.RFC822.get_parser_options());
        if (message == null) {
            throw new Error.INVALID("Unable to parse RFC 822 message");
        }

        this.from_gmime_message(message);
    }

    public async Message.from_composed_email(Geary.ComposedEmail email,
                                             string? message_id,
                                             GMime.EncodingConstraint constraint,
                                             GLib.Cancellable? cancellable)
        throws Error {
        this.message = new GMime.Message(true);

        //
        // Required headers

        this._from = email.from;
        foreach (RFC822.MailboxAddress mailbox in email.from) {
            this.message.add_mailbox(FROM, mailbox.name, mailbox.address);
        }

        this._date = email.date;
        this.message.set_date(this.date.value);

        // Optional headers

        if (email.to != null) {
            this._to = email.to;
            foreach (RFC822.MailboxAddress mailbox in email.to)
                this.message.add_mailbox(TO, mailbox.name, mailbox.address);
        }

        if (email.cc != null) {
            this._cc = email.cc;
            foreach (RFC822.MailboxAddress mailbox in email.cc)
                this.message.add_mailbox(CC, mailbox.name, mailbox.address);
        }

        if (email.bcc != null) {
            this._bcc = email.bcc;
            foreach (RFC822.MailboxAddress mailbox in email.bcc)
                this.message.add_mailbox(BCC, mailbox.name, mailbox.address);
        }

        if (email.sender != null) {
            this._sender = email.sender;
            this.message.add_mailbox(SENDER, this.sender.name, this.sender.address);
        }

        if (email.reply_to != null) {
            this._reply_to = email.reply_to;
            foreach (RFC822.MailboxAddress mailbox in email.reply_to)
                this.message.add_mailbox(REPLY_TO, mailbox.name, mailbox.address);
        }

        if (message_id != null) {
            this._message_id = new MessageID(message_id);
            this.message.set_message_id(message_id);
        }

        if (email.in_reply_to != null) {
            this._in_reply_to = email.in_reply_to;
            // We could use `this.message.add_mailbox()` in a similar way like
            // we did for the other headers, but this would require to change
            // the type of `email.in_reply_to` and `this.in_reply_to` from
            // `RFC822.MessageIDList` to `RFC822.MailboxAddresses`.
            this.message.set_header(HEADER_IN_REPLY_TO,
                                    email.in_reply_to.to_rfc822_string(),
                                    Geary.RFC822.get_charset());
        }

        if (email.references != null) {
            this._references = email.references;
            this.message.set_header(HEADER_REFERENCES,
                                    email.references.to_rfc822_string(),
                                    Geary.RFC822.get_charset());
        }

        if (email.subject != null) {
            this._subject = email.subject;
            this.message.set_subject(email.subject.value,
                                     Geary.RFC822.get_charset());
        }

        // User-Agent
        if (!Geary.String.is_empty(email.mailer)) {
            this.mailer = email.mailer;
            this.message.set_header(HEADER_MAILER, email.mailer,
                                    Geary.RFC822.get_charset());
        }

        // Build the message's body mime parts

        Gee.List<GMime.Object> body_parts = new Gee.LinkedList<GMime.Object>();

        // Share the body charset between plain and HTML parts, so we
        // don't need to work it out twice. This doesn't work for the
        // content encoding however since the HTML encoding may need
        // to be different, e.g. if it contains lines longer than
        // allowed by RFC822/SMTP.
        string? body_charset = null;

        // Body: text format (optional)
        if (email.body_text != null) {
            GMime.Part? body_text = null;
            try {
                body_text = yield body_data_to_part(
                    email.body_text.data,
                    null,
                    "text/plain",
                    true,
                    constraint,
                    cancellable
                );
            } catch (GLib.Error err) {
                warning("Error creating text body part: %s", err.message);
            }
            if (body_text != null) {
                body_charset = body_text.get_content_type().get_parameter(
                    "charset"
                );
                body_parts.add(body_text);
            }
        }

        // Body: HTML format (also optional)
        if (email.body_html != null) {
            const string CID_URL_PREFIX = "cid:";
            Gee.List<GMime.Object> related_parts =
                new Gee.LinkedList<GMime.Object>();

            // The files that need to have Content IDs assigned
            Gee.Map<string,Memory.Buffer> inline_files = new Gee.HashMap<string,Memory.Buffer>();
            inline_files.set_all(email.inline_files);

            // Create parts for inline images, if any, and updating
            // the IMG SRC attributes as we go. An inline file is only
            // included if it is actually referenced by the HTML - it
            // may have been deleted by the user after being added.

            // First, treat parts that already have Content Ids
            // assigned
            foreach (string cid in email.cid_files.keys) {
                if (email.contains_inline_img_src(CID_URL_PREFIX + cid)) {
                    GMime.Object? inline_part = null;
                    try {
                        inline_part = yield get_buffer_part(
                            email.cid_files[cid],
                            GLib.Path.get_basename(cid),
                            Geary.Mime.DispositionType.INLINE,
                            cancellable
                        );
                    } catch (GLib.Error err) {
                        warning(
                            "Error creating CID part %s: %s",
                            cid,
                            err.message
                        );
                    }
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
                        GMime.Object? inline_part = null;
                        try {
                            inline_part = yield get_buffer_part(
                                inline_files[name],
                                GLib.Path.get_basename(name),
                                Geary.Mime.DispositionType.INLINE,
                                cancellable
                            );
                        } catch (GLib.Error err) {
                            warning(
                                "Error creating inline file part %s: %s",
                                name,
                                err.message
                            );
                        }
                        if (inline_part != null) {
                            inline_part.set_content_id(cid);
                            related_parts.add(inline_part);
                        }
                    }
                }
            }

            GMime.Object? body_html = null;
            try {
                body_html = yield body_data_to_part(
                    email.body_html.data,
                    body_charset,
                    "text/html",
                    false,
                    constraint,
                    cancellable
                );
            } catch (GLib.Error err) {
                warning("Error creating html body part: %s", err.message);
            }

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
            GMime.Object? attachment_part = null;
            try {
                attachment_part = yield get_file_part(
                    file,
                    Geary.Mime.DispositionType.ATTACHMENT,
                    cancellable
                );
            } catch (GLib.Error err) {
                warning(
                    "Error creating attachment file part %s: %s",
                    file.get_path(),
                    err.message
                );
            }
            if (attachment_part != null) {
                attachment_parts.add(attachment_part);
            }
        }
        GMime.Object? attachment_part = coalesce_parts(attachment_parts, "mixed");
        if (attachment_part != null)
            main_parts.add(attachment_part);

        GMime.Object? main_part = coalesce_parts(main_parts, "mixed");
        this.message.set_mime_part(main_part);
    }

    private GMime.Object? coalesce_related(Gee.List<GMime.Object> parts,
                                           string type) {
        GMime.Object? part = coalesce_parts(parts, "related");
        if (parts.size > 1) {
            part.set_header("Type", type, Geary.RFC822.get_charset());
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

    private async GMime.Part? get_file_part(File file,
                                            Geary.Mime.DispositionType disposition,
                                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        FileInfo file_info = yield file.query_info_async(
            FileAttribute.STANDARD_CONTENT_TYPE,
            FileQueryInfoFlags.NONE
        );

        GMime.Part part = new GMime.Part();
        part.set_disposition(disposition.serialize());
        part.set_filename(file.get_basename());

        GMime.ContentType content_type = GMime.ContentType.parse(
            Geary.RFC822.get_parser_options(),
            file_info.get_content_type()
        );
        part.set_content_type(content_type);

        // Always use a binary encoding since even when attaching
        // text/plain parts, the line ending must always be preserved
        // and this is not possible without a binary encoding. See
        // https://gitlab.gnome.org/GNOME/geary/-/issues/1001
        //
        // TODO: The actual content encoding should be set based on
        // the IMAP/SMTP server's supported encoding. For example, if
        // 8-bit or binary is supported, then those should be used
        // instead of Base64.
        part.set_content_encoding(BASE64);

        GMime.StreamGIO stream = new GMime.StreamGIO(file);
        stream.set_owner(false);
        part.set_content(
            new GMime.DataWrapper.with_stream(
                stream, GMime.ContentEncoding.BINARY
            )
        );

        return part;
    }

    /**
     * Create a GMime part for the provided attachment buffer
     */
    private async GMime.Part? get_buffer_part(Memory.Buffer buffer,
                                              string basename,
                                              Geary.Mime.DispositionType disposition,
                                              GLib.Cancellable? cancellable)
        throws GLib.Error {
        Mime.ContentType? mime_type = Mime.ContentType.guess_type(
            basename,
            buffer
        );

        if (mime_type == null) {
            throw new Error.INVALID(
                _("Could not determine mime type for “%s”.").printf(basename)
                );
        }

        GMime.ContentType? content_type = GMime.ContentType.parse(
            Geary.RFC822.get_parser_options(),
            mime_type.get_mime_type()
        );

        if (content_type == null) {
            throw new Error.INVALID(
                _("Could not determine content type for mime type “%s” on “%s”.").printf(mime_type.to_string(), basename)
                );
        }

        GMime.Part part = new GMime.Part();
        part.set_disposition(disposition.serialize());
        part.set_filename(basename);
        part.set_content_type(content_type);

        // Always use a binary encoding since even when attaching
        // text/plain parts, the line ending must always be preserved
        // and this is not possible without a binary encoding. See
        // https://gitlab.gnome.org/GNOME/geary/-/issues/1001
        //
        // TODO: The actual content encoding should be set based on
        // the IMAP/SMTP server's supported encoding. For example, if
        // 8-bit or binary is supported, then those should be used
        // instead of Base64.
        part.set_content_encoding(BASE64);

        GMime.StreamMem stream = Utils.create_stream_mem(buffer);
        part.set_content(
            new GMime.DataWrapper.with_stream(
                stream, GMime.ContentEncoding.BINARY
            )
        );

        return part;
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
     * Returns the header of the message.
     */
    public Header get_header() {
        return new Header.from_gmime(this.message);
    }

    /**
     * Returns the body of the message.
     */
    public Text get_body() {
        Text? body = null;
        GMime.Object? gmime = this.message.get_mime_part();
        if (gmime != null) {
            var stream = new GMime.StreamMem();

            // GMime doesn't support writing content-only via the
            // public API, so suppress all headers in the message
            // instead.
            GMime.FormatOptions options = Geary.RFC822.get_format_options().clone();
            GMime.HeaderList headers = message.get_header_list();
            int count = headers.get_count();
            for (int i = 0; i < count; i++) {
                options.add_hidden_header(headers.get_header_at(i).get_name());
            }
            gmime.write_to_stream(options, stream);
            body = new Text.from_gmime(stream);
        } else {
            body = new Text(Memory.EmptyBuffer.instance);
        }
        return body;
    }

    /**
     * Serialises the message using native (i.e. LF) line endings.
     */
    public Memory.Buffer get_native_buffer() throws Error {
        return message_to_memory_buffer(false, NONE);
    }

    /**
     * Serialises the message using RFC 822 (i.e. CRLF) line endings.
     *
     * Returns the message as a memory buffer suitable for network
     * transmission and interoperability with other RFC 822 consumers.
     */
    public Memory.Buffer get_rfc822_buffer(RFC822FormatOptions options = NONE)
        throws Error {
        return message_to_memory_buffer(true, options);
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
                part.content_type.is_type("text", text_subtype)
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
        throws Error {
        Part part = new Part(node);
        Mime.ContentType content_type = part.content_type;

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
                    Part.EncodingConversion.UTF8,
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
        throws Error {
        string? body = null;
        if (!construct_body_from_mime_parts(message.get_mime_part(), Mime.MultipartSubtype.UNSPECIFIED,
            text_subtype, to_html, replacer, ref body)) {
            throw new Error.NOT_FOUND("Could not find any \"text/%s\" parts", text_subtype);
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
     * @throws Error.NOT_FOUND if an HTML body is not present.
     */
    public string? get_html_body(InlinePartReplacer? replacer) throws Error {
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
     * @throws Error.NOT_FOUND if a plaintext body is not present.
     */
    public string? get_plain_body(bool convert_to_html, InlinePartReplacer? replacer)
        throws Error {
        return internal_get_body("plain", convert_to_html, replacer);
    }

    /**
     * Return the body as a searchable string.  The body in this case should
     * include everything visible in the message's body in the client, which
     * would be only one body part, plus any visible attachments (which can be
     * disabled by passing false in include_sub_messages).  Note that values
     * that come out of this function are persisted.
     */
    public string? get_searchable_body(bool include_sub_messages = true)
        throws Error {
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
        Mime.DispositionType disposition = Mime.DispositionType.UNSPECIFIED)
        throws Error {
        Gee.List<Part> attachments = new Gee.LinkedList<Part>();
        get_attachments_recursively(attachments, message.get_mime_part(), disposition);
        return attachments;
    }

    private MailboxAddresses? to_addresses(GMime.InternetAddressList? list)
        throws Error {
        MailboxAddresses? addresses = null;
        if (list != null && list.length() > 0) {
            addresses = new MailboxAddresses.from_gmime(list);
        }
        return addresses;
    }

    private MessageIDList? append_message_id(MessageIDList? existing,
                                            string header_value)
        throws Error {
        MessageIDList? ids = existing;
        if (!String.is_empty_or_whitespace(header_value)) {
            try {
                ids = new MessageIDList.from_rfc822_string(header_value);
                if (existing != null) {
                    ids = existing.concatenate_list(ids);
                }
            } catch (Error err) {
                // Can't simply throw this since we need to be as lax as
                // possible when decoding messages. Hence just log it.
                debug("Error parsing message id list: %s", err.message);
            }
        }
        return ids;
    }

    private void get_attachments_recursively(Gee.List<Part> attachments,
                                             GMime.Object root,
                                             Mime.DispositionType requested_disposition)
        throws Error {
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
                message.write_to_stream(Geary.RFC822.get_format_options(), stream);
                GMime.DataWrapper data = new GMime.DataWrapper.with_stream(stream,
                    GMime.ContentEncoding.BINARY);  // Equivalent to no encoding
                GMime.Part part = new GMime.Part.with_type("message", "rfc822");
                part.set_content(data);
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
                Mime.ContentType content_type = part.content_type;

#if WITH_TNEF_SUPPORT
                if (content_type.is_type("application", "vnd.ms-tnef")) {
                    GMime.StreamMem stream = new GMime.StreamMem();
                    ((GMime.Part) root).get_content().write_to_stream(stream);
                    ByteArray tnef_data = stream.get_byte_array();
                    Ytnef.TNEFStruct tn = Ytnef.TNEFStruct();
                    if (Ytnef.ParseMemory(tnef_data.data, ref tn) == 0) {
                        for (unowned Ytnef.Attachment? a = tn.starting_attach.next; a != null; a = a.next) {
                            attachments.add(new Part(tnef_attachment_to_gmime_part(a)));
                        }
                    }
                } else
#endif // WITH_TNEF_SUPPORT
                if (actual_disposition == Mime.DispositionType.ATTACHMENT ||
                    (!content_type.is_type("text", "plain") &&
                     !content_type.is_type("text", "html"))) {
                    // Skip text/plain and text/html parts that are INLINE
                    // or UNSPECIFIED, as they will be included in the body
                    attachments.add(part);
                }
            }
        }
    }

#if WITH_TNEF_SUPPORT
    private GMime.Part tnef_attachment_to_gmime_part(Ytnef.Attachment a) {
        Ytnef.VariableLength* filenameProp = Ytnef.MAPIFindProperty(a.MAPI, Ytnef.PROP_TAG(Ytnef.PropType.STRING8, Ytnef.PropID.ATTACH_LONG_FILENAME));
        if (filenameProp == Ytnef.MAPI_UNDEFINED) {
            filenameProp = Ytnef.MAPIFindProperty(a.MAPI, Ytnef.PROP_TAG(Ytnef.PropType.STRING8, Ytnef.PropID.DISPLAY_NAME));
            if (filenameProp == Ytnef.MAPI_UNDEFINED) {
                filenameProp = &a.Title;
            }
        }
        string filename = (string) filenameProp.data;
        uint8[] data = Bytes.unref_to_data(new Bytes(a.FileData.data));

        GMime.Part part = new GMime.Part.with_type("text", "plain");
        part.set_filename(filename);
        part.set_content_type(GMime.ContentType.parse(Geary.RFC822.get_parser_options(), GLib.ContentType.guess(filename, data, null)));
        part.set_content(new GMime.DataWrapper.with_stream(new GMime.StreamMem.with_buffer(data), GMime.ContentEncoding.BINARY));
        return part;
    }
#endif

    public Gee.List<Geary.RFC822.Message> get_sub_messages()
        throws Error {
        Gee.List<Geary.RFC822.Message> messages = new Gee.ArrayList<Geary.RFC822.Message>();
        find_sub_messages(messages, message.get_mime_part());
        return messages;
    }

    private void find_sub_messages(Gee.List<Message> messages,
                                   GMime.Object root)
        throws Error {
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
                messages.add(new Message.from_gmime_message(sub_message));
            } else {
                warning("Corrupt message, possibly bug 769697");
            }
        }
    }

    private Memory.Buffer message_to_memory_buffer(bool encode_lf,
                                                   RFC822FormatOptions options)
        throws Error {
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);

        GMime.StreamFilter stream_filter = new GMime.StreamFilter(stream);
        if (encode_lf) {
            stream_filter.add(new GMime.FilterUnix2Dos(false));
        } else {
            stream_filter.add(new GMime.FilterDos2Unix(false));
        }
        if (RFC822FormatOptions.SMTP_FORMAT in options) {
            stream_filter.add(new GMime.FilterSmtpData());
        }

        var format = Geary.RFC822.get_format_options();
        if (RFC822FormatOptions.SMTP_FORMAT in options) {
            format = format.clone();
            format.add_hidden_header("Bcc");
        }

        if (message.write_to_stream(format, stream_filter) < 0) {
            throw new Error.FAILED(
                "Unable to write RFC822 message to filter stream"
            );
        }

        if (stream_filter.flush() != 0) {
            throw new Error.FAILED(
                "Unable to flush RFC822 message to memory stream"
            );
        }

        if (stream.flush() != 0) {
            throw new Error.FAILED(
                "Unable to flush RFC822 message to memory buffer"
            );
        }

        return new Memory.ByteBuffer.from_byte_array(byte_array);
    }

    public string to_string() {
        return message.to_string(Geary.RFC822.get_format_options());
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
    private async GMime.Part body_data_to_part(uint8[] content,
                                               string? charset,
                                               string content_type,
                                               bool is_flowed,
                                               GMime.EncodingConstraint constraint,
                                               GLib.Cancellable? cancellable)
        throws GLib.Error {
        GMime.Stream content_stream = new GMime.StreamMem.with_buffer(content);
        if (charset == null) {
            charset = yield Utils.get_best_charset(content_stream, cancellable);
        }
        GMime.StreamFilter filter_stream = new GMime.StreamFilter(content_stream);
        filter_stream.add(new GMime.FilterCharset(UTF8_CHARSET, charset));

        GMime.ContentEncoding encoding = yield Utils.get_best_encoding(
            filter_stream,
            constraint,
            cancellable
        );

        if (is_flowed && encoding == GMime.ContentEncoding.BASE64) {
            // Base64-encoded text needs to have CR's added after LF's
            // before encoding, otherwise it breaks format=flowed. See
            // Bug 753528.
            filter_stream.add(new GMime.FilterUnix2Dos(false));
        }

        GMime.ContentType complete_type = GMime.ContentType.parse(
                                              Geary.RFC822.get_parser_options(),
                                              content_type
                                          );
        complete_type.set_parameter("charset", charset);
        if (is_flowed) {
            complete_type.set_parameter("format", "flowed");
        }

        GMime.DataWrapper body = new GMime.DataWrapper.with_stream(
            filter_stream, GMime.ContentEncoding.DEFAULT
        );

        GMime.Part body_part = new GMime.Part.with_type("text", "plain");
        body_part.set_content_type(complete_type);
        body_part.set_content(body);
        body_part.set_content_encoding(encoding);
        return body_part;
    }

}
