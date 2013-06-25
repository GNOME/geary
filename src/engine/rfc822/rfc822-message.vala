/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.RFC822.Message : BaseObject {
    private const string DEFAULT_ENCODING = "UTF8";
    
    private const string HEADER_IN_REPLY_TO = "In-Reply-To";
    private const string HEADER_REFERENCES = "References";
    private const string HEADER_MAILER = "X-Mailer";
    
    // Internal note: If a field is added here, it *must* be set in Message.from_parts(),
    // Message.without_bcc(), and stock_from_gmime().
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
    
    public Message(Full full) throws RFC822Error {
        GMime.Parser parser = new GMime.Parser.with_stream(Utils.create_stream_mem(full.buffer));
        
        message = parser.construct_message();
        if (message == null)
            throw new RFC822Error.INVALID("Unable to parse RFC 822 message");
        
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
        
        stock_from_gmime();
    }

    public Message.from_composed_email(Geary.ComposedEmail email) {
        message = new GMime.Message(true);
        
        // Required headers
        assert(email.from.size > 0);
        sender = email.from[0];
        message.set_sender(sender.to_rfc822_string());
        message.set_date((time_t) email.date.to_unix(),
            (int) (email.date.get_utc_offset() / TimeSpan.HOUR));
        
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
        message = new GMime.Message(true);
        
        // Required headers.
        sender = email.sender;
        message.set_sender(email.message.get_sender());
        
        date = email.date;
        message.set_date_as_string(email.date.to_string());
        
        // Optional headers.
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

        if (email.in_reply_to != null) {
            in_reply_to = email.in_reply_to;
            message.set_header(HEADER_IN_REPLY_TO, email.in_reply_to.value);
        }

        if (email.references != null) {
            references = email.references;
            message.set_header(HEADER_REFERENCES, email.references.to_rfc822_string());
        }

        if (email.subject != null) {
            subject = email.subject;
            message.set_subject(email.subject.value);
        }

        // User-Agent
        if (!Geary.String.is_empty(email.mailer)) {
            mailer = email.mailer;
            message.set_header(HEADER_MAILER, email.mailer);
        }
        
        // Setup body depending on what MIME components were filled out.
        message.set_mime_part(email.message.get_mime_part());
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
    
    public Geary.Email get_email(int position, Geary.EmailIdentifier id) throws Error {
        Geary.Email email = new Geary.Email(position, id);
        
        email.set_message_header(new Geary.RFC822.Header(new Geary.Memory.StringBuffer(
            message.get_headers())));
        email.set_send_date(date);
        email.set_originators(from, new Geary.RFC822.MailboxAddresses.single(sender), null);
        email.set_receivers(to, cc, bcc);
        email.set_full_references(null, in_reply_to, references);
        email.set_message_subject(subject);
        email.set_message_body(new Geary.RFC822.Text(new Geary.Memory.StringBuffer(
            message.get_body().to_string())));
        email.set_message_preview(new Geary.RFC822.PreviewText.from_string(get_preview()));
        
        return email;
    }
    
    // Takes an e-mail object with a body and generates a preview.  If there is no body
    // or the body is the empty string, the empty string will be returned.
    public string get_preview() {
        string? preview = null;
        try {
            preview = get_text_body(false);
        } catch (Error e) {
            try {
                preview = Geary.HTML.remove_html_tags(get_html_body());
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
    
    public Memory.Buffer get_body_rfc822_buffer() {
        return new Geary.Memory.StringBuffer(message.to_string());
    }
    
    public Memory.Buffer get_first_mime_part_of_content_type(string content_type, bool to_html = false)
        throws RFC822Error {
        // search for content type starting from the root
        GMime.Part? part = find_first_mime_part(message.get_mime_part(), content_type);
        if (part == null) {
            throw new RFC822Error.NOT_FOUND("Could not find a MIME part with content-type %s",
                content_type);
        }
        
        // convert payload to a buffer
        return mime_part_to_memory_buffer(part, true, to_html);
    }

    private GMime.Part? find_first_mime_part(GMime.Object current_root, string content_type) {
        // descend looking for the content type in a GMime.Part
        GMime.Multipart? multipart = current_root as GMime.Multipart;
        if (multipart != null) {
            int count = multipart.get_count();
            for (int ctr = 0; ctr < count; ctr++) {
                GMime.Part? child_part = find_first_mime_part(multipart.get_part(ctr), content_type);
                if (child_part != null)
                    return child_part;
            }
        }

        GMime.Part? part = current_root as GMime.Part;
        if (part != null && String.nullable_stri_equal(part.get_content_type().to_string(), content_type) &&
            !String.nullable_stri_equal(part.get_disposition(), "attachment")) {
            return part;
        }

        return null;
    }

    public string? get_html_body() throws RFC822Error {
        return get_first_mime_part_of_content_type("text/html").to_string();
    }
    
    public string? get_text_body(bool convert_to_html = true) throws RFC822Error {
        return get_first_mime_part_of_content_type("text/plain", convert_to_html).to_string();
    }
    
    // Returns a body of the email as HTML.  The "html_format" flag tells it whether to try for a
    // HTML format body or plain text body first.  But if it doesn't find that one, it'll return
    // the other.
    public string? get_body(bool html_format) throws RFC822Error {
        try {
            return html_format ? get_html_body() : get_text_body();
        } catch (Error error) {
            return html_format ? get_text_body() : get_html_body();
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
            body = get_html_body();
            html = true;
        } catch (Error e) {
            try {
                body = get_text_body(false);
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
        if (part == null) {
            throw new RFC822Error.NOT_FOUND("Could not find a MIME part with content-id %s",
                mime_id);
        }
        return mime_part_to_memory_buffer(part);
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

    internal Gee.List<GMime.Part> get_attachments() throws RFC822Error {
        Gee.List<GMime.Part> attachments = new Gee.ArrayList<GMime.Part>();
        find_attachments(attachments, message.get_mime_part() );
        return attachments;
    }

    private void find_attachments(Gee.List<GMime.Part> attachments, GMime.Object root)
        throws RFC822Error {

        // If this is a multipart container, dive into each of its children.
        if (root is GMime.Multipart) {
            GMime.Multipart multipart = root as GMime.Multipart;
            int count = multipart.get_count();
            for (int i = 0; i < count; ++i) {
                find_attachments(attachments, multipart.get_part(i));
            }
            return;
        }

        // Otherwise see if it has a content disposition of "attachment."
        if (root is GMime.Part && String.nullable_stri_equal(root.get_disposition(), "attachment")) {
            attachments.add(root as GMime.Part);
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
            messages.add(new Geary.RFC822.Message.from_gmime_message(sub_message));
        }
    }

    private Memory.Buffer mime_part_to_memory_buffer(GMime.Part part,
        bool to_utf8 = false, bool to_html = false) throws RFC822Error {

        GMime.DataWrapper? wrapper = part.get_content_object();
        if (wrapper == null) {
            throw new RFC822Error.INVALID("Could not get the content wrapper for content-type %s",
                part.get_content_type().to_string());
        }
        
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);
        
        // Convert encoding to UTF-8.
        GMime.StreamFilter stream_filter = new GMime.StreamFilter(stream);
        if (to_utf8) {
            string? charset = part.get_content_type_parameter("charset");
            if (String.is_empty(charset))
                charset = DEFAULT_ENCODING;
            stream_filter.add(Geary.RFC822.Utils.create_utf8_filter_charset(charset));
        }
        string format = part.get_content_type_parameter("format") ?? "";
        bool flowed = (format.down() == "flowed");
        string delsp_par = part.get_content_type_parameter("DelSp") ?? "no";
        bool delsp = (delsp_par.down() == "yes");
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

