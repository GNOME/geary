/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.RFC822.Message : BaseObject {
    /**
     * This delegate is an optional parameter to the body constructers that allows callers
     * to process arbitrary non-text, inline MIME parts.
     */
    public delegate string? InlinePartReplacer(string filename, Mime.ContentType? content_type,
        Mime.ContentDisposition? disposition, Geary.Memory.Buffer buffer);
    
    private const string DEFAULT_ENCODING = "UTF8";
    
    private const string HEADER_IN_REPLY_TO = "In-Reply-To";
    private const string HEADER_REFERENCES = "References";
    private const string HEADER_MAILER = "X-Mailer";
    private const string HEADER_BCC = "Bcc";
    
    // Internal note: If a field is added here, it *must* be set in stock_from_gmime().
    public RFC822.MailboxAddress? sender { get; private set; default = null; }
    public RFC822.MailboxAddresses? from { get; private set; default = null; }
    public RFC822.MailboxAddresses? to { get; private set; default = null; }
    public RFC822.MailboxAddresses? cc { get; private set; default = null; }
    public RFC822.MailboxAddresses? bcc { get; private set; default = null; }
    public RFC822.MessageID? in_reply_to { get; private set; default = null; }
    public RFC822.MessageIDList? references { get; private set; default = null; }
    public RFC822.Subject? subject { get; private set; default = null; }
    public string? mailer { get; private set; default = null; }
    public Geary.RFC822.Date? date { get; private set; default = null; }
    
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
        // Had some problems with GMime not parsing a message when using a StreamCat, so
        // manually copy them into a single buffer and decode that way; see
        // http://redmine.yorba.org/issues/7034
        // and
        // https://bugzilla.gnome.org/show_bug.cgi?id=701572
        //
        // TODO: When fixed in GMime, return to original behavior of streaming each buffer in
        uint8[] buffer = new uint8[header.buffer.size + body.buffer.size];
        uint8* ptr = buffer;
        GLib.Memory.copy(ptr, header.buffer.get_bytes().get_data(), header.buffer.size);
        GLib.Memory.copy(ptr + header.buffer.size, body.buffer.get_bytes().get_data(), body.buffer.size);
        
        GMime.Parser parser = new GMime.Parser.with_stream(new GMime.StreamMem.with_buffer(buffer));
        message = parser.construct_message();
        if (message == null)
            throw new RFC822Error.INVALID("Unable to parse RFC 822 message");
        
        body_buffer = body.buffer;
        body_offset = 0;
        
        stock_from_gmime();
    }

    public Message.from_composed_email(Geary.ComposedEmail email, string? message_id) {
        message = new GMime.Message(true);
        
        // Required headers
        assert(email.from.size > 0);
        sender = email.from[0];
        date = new RFC822.Date.from_date_time(email.date);
        
        message.set_sender(sender.to_rfc822_string());
        message.set_date((time_t) email.date.to_unix(),
            (int) (email.date.get_utc_offset() / TimeSpan.HOUR));
        if (message_id != null)
            message.set_message_id(message_id);
        
        // Optional headers
        if (email.to != null) {
            to = email.to;
            foreach (RFC822.MailboxAddress mailbox in email.to)
                message.add_recipient(GMime.RecipientType.TO, mailbox.name, mailbox.address);
        }
        
        if (email.cc != null) {
            cc = email.cc;
            foreach (RFC822.MailboxAddress mailbox in email.cc)
                message.add_recipient(GMime.RecipientType.CC, mailbox.name, mailbox.address);
        }

        if (email.bcc != null) {
            bcc = email.bcc;
            foreach (RFC822.MailboxAddress mailbox in email.bcc)
                message.add_recipient(GMime.RecipientType.BCC, mailbox.name, mailbox.address);
        }

        if (email.in_reply_to != null) {
            in_reply_to = new Geary.RFC822.MessageID(email.in_reply_to);
            message.set_header(HEADER_IN_REPLY_TO, email.in_reply_to);
        }
        
        if (email.references != null) {
            references = new Geary.RFC822.MessageIDList.from_rfc822_string(email.references);
            message.set_header(HEADER_REFERENCES, email.references);
        }
        
        if (email.subject != null) {
            subject = new Geary.RFC822.Subject(email.subject);
            message.set_subject(email.subject);
        }

        // User-Agent
        if (!Geary.String.is_empty(email.mailer)) {
            mailer = email.mailer;
            message.set_header(HEADER_MAILER, email.mailer);
        }

        // Body: text format (optional)
        GMime.Part? body_text = null;
        if (email.body_text != null) {
            GMime.StreamMem stream = new GMime.StreamMem.with_buffer(email.body_text.data);
            GMime.DataWrapper content = new GMime.DataWrapper.with_stream(stream,
                GMime.ContentEncoding.DEFAULT);
            
            body_text = new GMime.Part();
            body_text.set_content_type(new GMime.ContentType.from_string("text/plain; charset=utf-8; format=flowed"));
            body_text.set_content_object(content);
            body_text.set_content_encoding(Geary.RFC822.Utils.get_best_content_encoding(stream,
                GMime.EncodingConstraint.7BIT));
        }
        
        // Body: HTML format (also optional)
        GMime.Part? body_html = null;
        if (email.body_html != null) {
            GMime.StreamMem stream = new GMime.StreamMem.with_buffer(email.body_html.data);
            GMime.DataWrapper content = new GMime.DataWrapper.with_stream(stream,
                GMime.ContentEncoding.DEFAULT);
            
            body_html = new GMime.Part();
            body_html.set_content_type(new GMime.ContentType.from_string("text/html; charset=utf-8"));
            body_html.set_content_object(content);
            body_html.set_content_encoding(Geary.RFC822.Utils.get_best_content_encoding(stream,
                GMime.EncodingConstraint.7BIT));
        }
        
        // Build the message's mime part.
        Gee.List<GMime.Object> main_parts = new Gee.LinkedList<GMime.Object>();
        
        Gee.List<GMime.Object> body_parts = new Gee.LinkedList<GMime.Object>();
        if (body_text != null)
            body_parts.add(body_text);
        if (body_html != null)
            body_parts.add(body_html);
        GMime.Object? body_part = coalesce_parts(body_parts, "alternative");
        if (body_part != null)
            main_parts.add(body_part);
        
        Gee.List<GMime.Object> attachment_parts = new Gee.LinkedList<GMime.Object>();
        foreach (File attachment_file in email.attachment_files) {
            GMime.Object? attachment_part = get_attachment_part(attachment_file);
            if (attachment_part != null)
                attachment_parts.add(attachment_part);
        }
        GMime.Object? attachment_part = coalesce_parts(attachment_parts, "mixed");
        if (attachment_part != null)
            main_parts.add(attachment_part);
            
        GMime.Object? main_part = coalesce_parts(main_parts, "mixed");
        message.set_mime_part(main_part);
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
    
    private GMime.Part? get_attachment_part(File file) {
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
        part.set_disposition("attachment");
        part.set_filename(file.get_basename());
        part.set_content_type(new GMime.ContentType.from_string(file_info.get_content_type()));
        
        // This encoding is the initial encoding of the stream.
        GMime.StreamGIO stream = new GMime.StreamGIO(file);
        stream.set_owner(false);
        part.set_content_object(new GMime.DataWrapper.with_stream(stream, GMime.ContentEncoding.BINARY));
        
        // This encoding is the "Content-Transfer-Encoding", which GMime automatically converts to.
        part.set_content_encoding(Geary.RFC822.Utils.get_best_content_encoding(stream,
            GMime.EncodingConstraint.7BIT));
        
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
        email.set_originators(from, new Geary.RFC822.MailboxAddresses.single(sender), null);
        email.set_receivers(to, cc, bcc);
        email.set_full_references(null, in_reply_to, references);
        email.set_message_subject(subject);
        email.set_message_body(new Geary.RFC822.Text(new Geary.Memory.OffsetBuffer(
            body_buffer, body_offset)));
        email.set_message_preview(new Geary.RFC822.PreviewText.from_string(get_preview()));
        
        return email;
    }
    
    // Takes an e-mail object with a body and generates a preview.  If there is no body
    // or the body is the empty string, the empty string will be returned.
    public string get_preview() {
        string? preview = null;
        try {
            preview = get_text_body(false, null);
        } catch (Error e) {
            try {
                preview = Geary.HTML.remove_html_tags(get_html_body(null));
            } catch (Error error) {
                debug("Could not generate message preview: %s\n and: %s", e.message, error.message);
            }
        }
        
        return Geary.String.safe_byte_substring((preview ?? "").chug(),
            Geary.Email.MAX_PREVIEW_BYTES);
    }
    
    private void stock_from_gmime() {
        string? message_sender = message.get_sender();
        if (message_sender != null) {
            from = new RFC822.MailboxAddresses.from_rfc822_string(message_sender);
            // sender is defined as first From address, from better or worse
            sender = (from.size != 0) ? from[0] : null;
        }
        
        Gee.List<RFC822.MailboxAddress>? converted = convert_gmime_address_list(
            message.get_recipients(GMime.RecipientType.TO));
        if (converted != null && converted.size > 0)
            to = new RFC822.MailboxAddresses(converted);
        
        converted = convert_gmime_address_list(message.get_recipients(GMime.RecipientType.CC));
        if (converted != null && converted.size > 0)
            cc = new RFC822.MailboxAddresses(converted);
        
        converted = convert_gmime_address_list(message.get_recipients(GMime.RecipientType.BCC));
        if (converted != null && converted.size > 0)
            bcc = new RFC822.MailboxAddresses(converted);
        
        if (!String.is_empty(message.get_header(HEADER_IN_REPLY_TO)))
            in_reply_to = new RFC822.MessageID(message.get_header(HEADER_IN_REPLY_TO));
        
        if (!String.is_empty(message.get_header(HEADER_REFERENCES)))
            references = new RFC822.MessageIDList.from_rfc822_string(message.get_header(HEADER_REFERENCES));
        
        if (!String.is_empty(message.get_subject()))
            subject = new RFC822.Subject.decode(message.get_subject());
        
        if (!String.is_empty(message.get_header(HEADER_MAILER)))
            mailer = message.get_header(HEADER_MAILER);
        
        if (!String.is_empty(message.get_date_as_string())) {
            try {
                date = new Geary.RFC822.Date(message.get_date_as_string());
            } catch (Error error) {
                debug("Could not get date from message: %s", error.message);
            }
        }
    }
    
    private Gee.List<RFC822.MailboxAddress>? convert_gmime_address_list(InternetAddressList? addrlist,
        int depth = 0) {
        if (addrlist == null || addrlist.length() == 0)
            return null;
        
        Gee.List<RFC822.MailboxAddress>? converted = new Gee.ArrayList<RFC822.MailboxAddress>();
        
        int length = addrlist.length();
        for (int ctr = 0; ctr < length; ctr++) {
            InternetAddress addr = addrlist.get_address(ctr);
            
            InternetAddressMailbox? mbox_addr = addr as InternetAddressMailbox;
            if (mbox_addr != null) {
                converted.add(new RFC822.MailboxAddress(mbox_addr.get_name(), mbox_addr.get_addr()));
                
                continue;
            }
            
            // Two problems here:
            //
            // First, GMime crashes when parsing a malformed group list (the case seen in the
            // wild is -- weirdly enough -- a date appended to the end of a cc: list on a spam
            // email.  GMime interprets it as a group list but segfaults when destroying the
            // InterneAddresses it generated from it.  See:
            // https://bugzilla.gnome.org/show_bug.cgi?id=695319
            //
            // Second, RFC 822 6.2.6: "This  standard  does  not  permit  recursive  specification
            // of groups within groups."  So don't do it.
            InternetAddressGroup? group = addr as InternetAddressGroup;
            if (group != null) {
                if (depth == 0) {
                    Gee.List<RFC822.MailboxAddress>? grouplist = convert_gmime_address_list(
                        group.get_members(), depth + 1);
                    if (grouplist != null)
                        converted.add_all(grouplist);
                }
                
                continue;
            }
            
            warning("Unknown InternetAddress in list: %s", addr.get_type().name());
        }
        
        return (converted.size > 0) ? converted : null;
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
     * This method is the main utility method used by the other body constructors. It calls itself
     * recursively via the last argument ("node").
     * 
     * The constructed body is stored in ref string? body. If the constructed body is null,
     * ref string? body remains unmodified.
     *
     * ref string? body is only modified if the constructed body is non-empty
     * 
     * Returns: a bool indicating whether a text part with the desired text_subtype was found
     */
    private bool construct_body_from_mime_parts(ref string? body, InlinePartReplacer? replacer,
        string text_subtype, bool allow_only_replaced, bool to_html, GMime.Object? node)
        throws RFC822Error {
        if (node == null) {
            node = message.get_mime_part();
        }
        
        // If this is a multipart, call ourselves recursively on the children
        GMime.Multipart? multipart = node as GMime.Multipart;
        if (multipart != null) {
            bool found_text_subtype = false;
            StringBuilder builder = new StringBuilder();
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                GMime.Object child = multipart.get_part(i);
                string? child_body = null;
                found_text_subtype |= construct_body_from_mime_parts(ref child_body, replacer,
                    text_subtype, allow_only_replaced, to_html, child);
                if (child_body != null)
                    builder.append(child_body);
            }
            
            if (!Geary.String.is_empty_or_whitespace(builder.str))
                body = builder.str;
            return found_text_subtype;
        }
        
        // Only process inline leaf parts
        GMime.Part? part = node as GMime.Part;
        if (part == null)
            return false;
        
        Mime.ContentDisposition? disposition = null;
        if (part.get_content_disposition() != null)
            disposition = new Mime.ContentDisposition.from_gmime(part.get_content_disposition());
        
        // Stop processing if the part is an attachment
        if (disposition != null && disposition.disposition_type == Mime.DispositionType.ATTACHMENT)
            return false;
        
        /* Handle text parts that are not attachments
         * They may have inline disposition, or they may have no disposition specified
         */
        Mime.ContentType? content_type = null;
        if (part.get_content_type() != null) {
            content_type = new Mime.ContentType.from_gmime(part.get_content_type());
            if (content_type.has_media_type("text")) {
                if (content_type.has_media_subtype(text_subtype)) {
                    body = mime_part_to_memory_buffer(part, true, to_html).to_string();
                    return true;
                }
                
                // We were the wrong kind of text part
                return false;
            }
        }
        
        // If images have no disposition, they are handled elsewhere; see #7299
        if (disposition == null || disposition.disposition_type == Mime.DispositionType.UNSPECIFIED)
            return false;
        
        if (replacer == null)
            return false;
        
        // Hand off to the replacer for processing
        string? replaced_part = replacer(RFC822.Utils.get_clean_attachment_filename(part), content_type,
            disposition, mime_part_to_memory_buffer(part));
        if (replaced_part != null)
            body = replaced_part;
        
        return allow_only_replaced && (replaced_part != null);
    }
    
    /**
     * A front-end to construct_body_from_mime_parts() that converts its output parameters into
     * something that front-facing methods want to return.
     *
     * The allow_only_replaced flag indicates if it's allowable for the method to return only the
     * InlinePartReplacer's returned text.  In other words, if only an inline MIME section is found
     * but no portion of text_subtype, allow_only_replaced indicates if the InlinePartReplacer's
     * returned text constitutes a "body".
     */
    private string? internal_get_body(bool allow_only_replaced, string text_subtype, bool to_html,
        InlinePartReplacer? replacer) throws RFC822Error {
        string? body = null;
        if (!construct_body_from_mime_parts(ref body, replacer, text_subtype, allow_only_replaced,
            to_html, null)) {
            throw new RFC822Error.NOT_FOUND("Could not find any \"text/%s\" parts", text_subtype);
        }
        
        return body;
    }
    
    /**
     * Returns the HTML portion of the message body, if present.
     *
     * Throws {@link RFC822Error.NOT_FOUND} if an HTML body is not present.
     */
    private string? get_html_body(InlinePartReplacer? replacer) throws RFC822Error {
        return internal_get_body(true, "html", false, replacer);
    }
    
    /**
     * Returns the plaintext portion of the message body, if present.
     *
     * The convert_to_html flag indicates if the plaintext body should be converted into HTML.
     * Note that the InlinePartReplacer's output is not converted; it's up to the caller to know
     * what format to return when invoked.
     *
     * Throws {@link RFC822Error.NOT_FOUND} if a plaintext body is not present.
     */
    private string? get_text_body(bool convert_to_html, InlinePartReplacer? replacer) throws RFC822Error {
        return internal_get_body(true, "plain", convert_to_html, replacer);
    }
    
    /**
     * Returns a body of the email as HTML.
     *
     * The html_format flag indicates whether to use the HTML portion of the message body or to
     * convert the plaintext portion into HTML.  If the requested portion is not present, the
     * method will fallback and attempt to return the other (converted to HTML, if necessary).
     * It is possible for html_format to be false and this method to return HTML (if plaintext
     * is unavailable).  Consider using {@link get_html_body} or {@link get_text_body} if finer
     * control is desired.
     *
     * Note that the InlinePartReplacer's output is never converted and should return HTML.
     *
     * Throws {@link RFC822Error.NOT_FOUND if neither format is available.
     */
    public string? get_body(bool html_format, InlinePartReplacer? replacer = null) throws RFC822Error {
        try {
            return html_format
                ? internal_get_body(false, "html", false, replacer)
                : internal_get_body(false, "plain", true, replacer);
        } catch (Error err) {
            return html_format
                ? internal_get_body(true, "plain", true, replacer)
                : internal_get_body(true, "html", false, replacer);
        }
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
                body = get_text_body(false, null);
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
        Gee.List<RFC822.MailboxAddress>? recipients = get_recipients();
        if (recipients == null)
            return null;
        
        return RFC822.MailboxAddress.list_to_string(recipients, "", (a) => a.to_searchable_string());
    }
    
    public Memory.Buffer get_content_by_mime_id(string mime_id) throws RFC822Error {
        GMime.Part? part = find_mime_part_by_mime_id(message.get_mime_part(), mime_id);
        if (part == null)
            throw new RFC822Error.NOT_FOUND("Could not find a MIME part with Content-ID %s", mime_id);
        
        return mime_part_to_memory_buffer(part);
    }
    
    public string? get_content_filename_by_mime_id(string mime_id) throws RFC822Error {
        GMime.Part? part = find_mime_part_by_mime_id(message.get_mime_part(), mime_id);
        if (part == null)
            throw new RFC822Error.NOT_FOUND("Could not find a MIME part with Content-ID %s", mime_id);
        
        return part.get_filename();
    }
    
    private GMime.Part? find_mime_part_by_mime_id(GMime.Object root, string mime_id) {
        // If this is a multipart container, check each of its children.
        if (root is GMime.Multipart) {
            GMime.Multipart multipart = root as GMime.Multipart;
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                GMime.Part? child_part = find_mime_part_by_mime_id(multipart.get_part(i), mime_id);
                if (child_part != null) {
                    return child_part;
                }
            }
        }

        // Otherwise, check this part's content id.
        GMime.Part? part = root as GMime.Part;
        if (part != null && part.get_content_id() == mime_id) {
            return part;
        }
        return null;
    }
    
    // UNSPECIFIED disposition means "return all Mime parts"
    internal Gee.List<GMime.Part> get_attachments(
        Mime.DispositionType disposition = Mime.DispositionType.UNSPECIFIED) throws RFC822Error {
        Gee.List<GMime.Part> attachments = new Gee.ArrayList<GMime.Part>();
        get_attachments_recursively(attachments, message.get_mime_part(), disposition);
        return attachments;
    }
    
    private void get_attachments_recursively(Gee.List<GMime.Part> attachments, GMime.Object root,
        Mime.DispositionType requested_disposition) throws RFC822Error {
        // If this is a multipart container, dive into each of its children.
        GMime.Multipart? multipart = root as GMime.Multipart;
        if (multipart != null) {
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                get_attachments_recursively(attachments, multipart.get_part(i), requested_disposition);
            }
            return;
        }
        
        // If this is an attached message, go through it.
        GMime.MessagePart? messagepart = root as GMime.MessagePart;
        if (messagepart != null) {
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
                attachments.add(part);
            }
            
            get_attachments_recursively(attachments, message.get_mime_part(),
                requested_disposition);
            return;
        }
        
        // Otherwise, check if this part should be an attachment
        GMime.Part? part = root as GMime.Part;
        if (part == null) {
            return;
        }
        
        Mime.DispositionType part_disposition = Mime.DispositionType.deserialize(part.get_disposition(),
            null);
        if (part_disposition == Mime.DispositionType.UNSPECIFIED)
            return;
        
        if (part.get_content_type() != null) {
            Mime.ContentType content_type = new Mime.ContentType.from_gmime(part.get_content_type());
            if (part_disposition == Mime.DispositionType.INLINE
                && content_type.has_media_type("text")
                && (content_type.has_media_subtype("html") || content_type.has_media_subtype("plain"))) {
                // these are part of the body
                return;
            }
        }
        
        // Catch remaining disposition-type matches
        if (requested_disposition == Mime.DispositionType.UNSPECIFIED || part_disposition == requested_disposition)
            attachments.add(part);
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
            messages.add(new Geary.RFC822.Message.from_gmime_message(sub_message));
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
    
    private Memory.Buffer mime_part_to_memory_buffer(GMime.Part part,
        bool to_utf8 = false, bool to_html = false) throws RFC822Error {
        Mime.ContentType? content_type = null;
        if (part.get_content_type() != null)
            content_type = new Mime.ContentType.from_gmime(part.get_content_type());
        
        GMime.DataWrapper? wrapper = part.get_content_object();
        if (wrapper == null) {
            throw new RFC822Error.INVALID("Could not get the content wrapper for content-type %s",
                content_type.to_string());
        }
        
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);
        
        // Convert encoding to UTF-8.
        GMime.StreamFilter stream_filter = new GMime.StreamFilter(stream);
        if (to_utf8) {
            string? charset = (content_type != null) ? content_type.params.get_value("charset") : null;
            if (String.is_empty(charset))
                charset = DEFAULT_ENCODING;
            stream_filter.add(Geary.RFC822.Utils.create_utf8_filter_charset(charset));
        }
        
        bool flowed = (content_type != null) ? content_type.params.has_value_ci("format", "flowed") : false;
        bool delsp = (content_type != null) ? content_type.params.has_value_ci("DelSp", "yes") : false;
        if (flowed)
            stream_filter.add(new Geary.RFC822.FilterFlowed(to_html, delsp));
        
        if (to_html) {
            if (!flowed)
                stream_filter.add(new Geary.RFC822.FilterPlain());
            // HTML filter does stupid stuff to \r, so get rid of them.
            stream_filter.add(new GMime.FilterCRLF(false, false));
            stream_filter.add(new GMime.FilterHTML(GMime.FILTER_HTML_CONVERT_URLS, 0));
            stream_filter.add(new Geary.RFC822.FilterBlockquotes());
        }

        wrapper.write_to_stream(stream_filter);
        stream_filter.flush();
        
        return new Geary.Memory.ByteBuffer.from_byte_array(byte_array);
    }

    public string to_string() {
        return message.to_string();
    }
}

