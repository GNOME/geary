/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.MessageRow {
    public int64 id { get; set; default = Db.INVALID_ROWID; }
    public Geary.Email.Field fields { get; set; default = Geary.Email.Field.NONE; }

    public string? date { get; set; default = null; }
    public int64 date_time_t { get; set; default = -1; }

    public string? from { get; set; default = null; }
    public string? sender { get; set; default = null; }
    public string? reply_to { get; set; default = null; }

    public string? to { get; set; default = null; }
    public string? cc { get; set; default = null; }
    public string? bcc { get; set; default = null; }

    public string? message_id { get; set; default = null; }
    public string? in_reply_to { get; set; default = null; }
    public string? references { get; set; default = null; }

    public string? subject { get; set; default = null; }

    public Memory.Buffer? header { get; set; default = null; }

    public Memory.Buffer? body { get; set; default = null; }

    public string? preview { get; set; default = null; }

    public string? email_flags { get; set; default = null; }
    public string? internaldate { get; set; default = null; }
    public int64 internaldate_time_t { get; set; default = -1; }
    public int64 rfc822_size { get; set; default = -1; }

    public MessageRow() {
    }

    public MessageRow.from_email(Geary.Email email) {
        set_from_email(email);
    }

    // Converts the current row of the Result object into fields.  It's vitally important that
    // the columns specified in requested_fields be present in Result.
    public MessageRow.from_result(Geary.Email.Field requested_fields, Db.Result results) throws Error {
        id = results.int64_for("id");

        // the available fields are an intersection of what's available in the database and
        // what was requested
        fields = requested_fields & results.int_for("fields");

        if (fields.is_all_set(Geary.Email.Field.DATE)) {
            date = results.string_for("date_field");
            date_time_t = results.int64_for("date_time_t");
        }

        if (fields.is_all_set(Geary.Email.Field.ORIGINATORS)) {
            from = results.string_for("from_field");
            sender = results.string_for("sender");
            reply_to = results.string_for("reply_to");
        }

        if (fields.is_all_set(Geary.Email.Field.RECEIVERS)) {
            to = results.string_for("to_field");
            cc = results.string_for("cc");
            bcc = results.string_for("bcc");
        }

        if (fields.is_all_set(Geary.Email.Field.REFERENCES)) {
            message_id = results.string_for("message_id");
            in_reply_to = results.string_for("in_reply_to");
            references = results.string_for("reference_ids");
        }

        if (fields.is_all_set(Geary.Email.Field.SUBJECT))
            subject = results.string_for("subject");

        if (fields.is_all_set(Geary.Email.Field.HEADER))
            header = results.string_buffer_for("header");

        if (fields.is_all_set(Geary.Email.Field.BODY))
            body = results.string_buffer_for("body");

        if (fields.is_all_set(Geary.Email.Field.PREVIEW))
            preview = results.string_for("preview");

        if (fields.is_all_set(Geary.Email.Field.FLAGS))
            email_flags = results.string_for("flags");

        if (fields.is_all_set(Geary.Email.Field.PROPERTIES)) {
            internaldate = results.string_for("internaldate");
            internaldate_time_t = results.int64_for("internaldate_time_t");
            rfc822_size = results.int64_for("rfc822_size");
        }
    }

    public Geary.Email to_email(ImapDB.EmailIdentifier id) throws Error {
        // Important to set something in the Email object if the field bit is set ... for example,
        // if the caller expects to see a DATE field, that field is set in the Email's bitmask,
        // even if the Date object is null
        Geary.Email email = new Geary.Email(id);

        if (fields.is_all_set(Geary.Email.Field.DATE)) {
            email.set_send_date(unflatten_date(date));
        }

        if (fields.is_all_set(Geary.Email.Field.ORIGINATORS)) {
            email.set_originators(unflatten_addresses(from),
                                  unflatten_address(sender),
                                  unflatten_addresses(reply_to));
        }

        if (fields.is_all_set(Geary.Email.Field.RECEIVERS)) {
            email.set_receivers(unflatten_addresses(to),
                                unflatten_addresses(cc),
                                unflatten_addresses(bcc));
        }

        if (fields.is_all_set(Geary.Email.Field.REFERENCES)) {
            email.set_full_references(
                unflatten_message_id(message_id),
                unflatten_message_id_list(in_reply_to),
                unflatten_message_id_list(references)
            );
        }

        if (fields.is_all_set(Geary.Email.Field.SUBJECT))
            email.set_message_subject(new RFC822.Subject.from_rfc822_string(subject ?? ""));

        if (fields.is_all_set(Geary.Email.Field.HEADER))
            email.set_message_header(new RFC822.Header(header ?? Memory.EmptyBuffer.instance));

        if (fields.is_all_set(Geary.Email.Field.BODY))
            email.set_message_body(new RFC822.Text(body ?? Memory.EmptyBuffer.instance));

        if (fields.is_all_set(Geary.Email.Field.PREVIEW))
            email.set_message_preview(new RFC822.PreviewText(new Geary.Memory.StringBuffer(preview ?? "")));

        if (fields.is_all_set(Geary.Email.Field.FLAGS))
            email.set_flags(get_generic_email_flags());

        if (fields.is_all_set(Geary.Email.Field.PROPERTIES)) {
            Imap.EmailProperties? properties = get_imap_email_properties();
            if (properties != null)
                email.set_email_properties(properties);
        }

        return email;
    }


    public Geary.Imap.EmailProperties? get_imap_email_properties() {
        if (internaldate == null || rfc822_size < 0)
            return null;

        Imap.InternalDate? constructed = null;
        try {
            constructed = Imap.InternalDate.decode(internaldate);
        } catch (Error err) {
            debug("Unable to construct internaldate object from \"%s\": %s", internaldate,
                err.message);

            return null;
        }

        return new Imap.EmailProperties(
            constructed, new Imap.RFC822Size(this.rfc822_size)
        );
    }

    public Geary.EmailFlags? get_generic_email_flags() {
        return (email_flags != null)
            ? new Geary.Imap.EmailFlags(Geary.Imap.MessageFlags.deserialize(email_flags))
            : null;
    }

    public void merge_from_remote(Geary.Email email) {
        set_from_email(email);
    }

    private void set_from_email(Geary.Email email) {
        // Although the fields bitmask might indicate various fields are set, they may still be
        // null if empty

        if (email.fields.is_all_set(Geary.Email.Field.DATE)) {
            date = (email.date != null) ? email.date.to_rfc822_string() : null;
            date_time_t = (email.date != null) ? email.date.value.to_unix() : -1;

            fields = fields.set(Geary.Email.Field.DATE);
        }

        if (email.fields.is_all_set(Geary.Email.Field.ORIGINATORS)) {
            from = flatten_addresses(email.from);
            sender = flatten_address(email.sender);
            reply_to = flatten_addresses(email.reply_to);

            fields = fields.set(Geary.Email.Field.ORIGINATORS);
        }

        if (email.fields.is_all_set(Geary.Email.Field.RECEIVERS)) {
            to = flatten_addresses(email.to);
            cc = flatten_addresses(email.cc);
            bcc = flatten_addresses(email.bcc);

            fields = fields.set(Geary.Email.Field.RECEIVERS);
        }

        if (email.fields.is_all_set(Geary.Email.Field.REFERENCES)) {
            message_id = (email.message_id != null) ? email.message_id.to_rfc822_string() : null;
            in_reply_to = (email.in_reply_to != null) ? email.in_reply_to.to_rfc822_string() : null;
            references = (email.references != null) ? email.references.to_rfc822_string() : null;

            fields = fields.set(Geary.Email.Field.REFERENCES);
        }

        if (email.fields.is_all_set(Geary.Email.Field.SUBJECT)) {
            subject = (email.subject != null) ? email.subject.to_rfc822_string() : null;

            fields = fields.set(Geary.Email.Field.SUBJECT);
        }

        if (email.fields.is_all_set(Geary.Email.Field.HEADER)) {
            header = (email.header != null) ? email.header.buffer : null;

            fields = fields.set(Geary.Email.Field.HEADER);
        }

        if (email.fields.is_all_set(Geary.Email.Field.BODY)) {
            body = (email.body != null) ? email.body.buffer : null;

            fields = fields.set(Geary.Email.Field.BODY);
        }

        if (email.fields.is_all_set(Geary.Email.Field.PREVIEW)) {
            preview = (email.preview != null) ? email.preview.buffer.to_string() : null;

            fields = fields.set(Geary.Email.Field.PREVIEW);
        }

        if (email.fields.is_all_set(Geary.Email.Field.FLAGS)) {
            Geary.Imap.EmailFlags? imap_flags = (Geary.Imap.EmailFlags) email.email_flags;
            email_flags = (imap_flags != null) ? imap_flags.message_flags.serialize() : null;

            fields = fields.set(Geary.Email.Field.FLAGS);
        }

        if (email.fields.is_all_set(Geary.Email.Field.PROPERTIES)) {
            Geary.Imap.EmailProperties? imap_properties = (Geary.Imap.EmailProperties) email.properties;
            internaldate = (imap_properties != null) ? imap_properties.internaldate.serialize() : null;
            internaldate_time_t = (imap_properties != null) ? imap_properties.internaldate.value.to_unix() : -1;
            rfc822_size = (imap_properties != null) ? imap_properties.rfc822_size.value : -1;

            fields = fields.set(Geary.Email.Field.PROPERTIES);
        }
    }

    private static string? flatten_address(RFC822.MailboxAddress? addr) {
        string? flat = null;
        if (addr != null) {
            flat = addr.to_rfc822_string();
        }
        return flat;
    }

    private static string? flatten_addresses(RFC822.MailboxAddresses? addrs) {
        return (addrs == null || addrs.size == 0) ? null : addrs.to_rfc822_string();
    }

    private RFC822.Date? unflatten_date(string? str) {
        RFC822.Date? date = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                date = new RFC822.Date.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 date \"%s\": %s", str, err.message);
            }
        }
        return date;
    }

    private RFC822.MailboxAddress? unflatten_address(string? str) {
        RFC822.MailboxAddress? address = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                address = new RFC822.MailboxAddress.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 mailbox address \"%s\": %s", str, err.message);
            }
        }
        return address;
    }

    private RFC822.MailboxAddresses? unflatten_addresses(string? str) {
        RFC822.MailboxAddresses? addresses = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                addresses = new RFC822.MailboxAddresses.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 mailbox addresses \"%s\": %s", str, err.message);
            }
        }
        return addresses;
    }

    private RFC822.MessageID? unflatten_message_id(string? str) {
        RFC822.MessageID? id = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                id = new RFC822.MessageID.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 message id \"%s\": %s", str, err.message);
            }
        }
        return id;
    }

    private RFC822.MessageIDList? unflatten_message_id_list(string? str) {
        RFC822.MessageIDList? ids = null;
        if (!String.is_empty_or_whitespace(str)) {
            try {
                ids = new RFC822.MessageIDList.from_rfc822_string(str);
            } catch (RFC822.Error err) {
                // There's not much we can do here aside from logging
                // the error, since a lot of email just contain
                // invalid addresses
                debug("Invalid RFC822 message id \"%s\": %s", str, err.message);
            }
        }
        return ids;
    }

}
