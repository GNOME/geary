/* Copyright 2011-2015 Yorba Foundation
 * Portions copyright (C) 2000-2013 Jeffrey Stedfast
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.RFC822.Utils {

// We use DEL to mark quote levels, since it's unlikely to be in email bodies, is a single byte
// in UTF-8, and is unmolested by GMime.FilterHTML.
public const char QUOTE_MARKER = '\x7f';

public GMime.FilterCharset create_utf8_filter_charset(string from_charset) {
    GMime.FilterCharset? filter_charset = new GMime.FilterCharset(from_charset, "UTF-8");
    if (filter_charset == null) {
        debug("Unknown charset %s; treating as UTF-8", from_charset);
        filter_charset = new GMime.FilterCharset("UTF-8", "UTF-8");
        assert(filter_charset != null);
    }
    return filter_charset;
}

/**
 * Uses the best-possible transfer of bytes from the Memory.Buffer to the GMime.StreamMem object.
 * The StreamMem object should be destroyed *before* the Memory.Buffer object, since this method
 * will use unowned variants whenever possible.
 */
public GMime.StreamMem create_stream_mem(Memory.Buffer buffer) {
    Memory.UnownedByteArrayBuffer? unowned_bytes_array_buffer = buffer as Memory.UnownedByteArrayBuffer;
    if (unowned_bytes_array_buffer != null) {
        // set_byte_array doesn't do any copying and doesn't take ownership -- perfect, this is
        // the best of all possible worlds, assuming the Memory.Buffer is not destroyed first
        GMime.StreamMem stream = new GMime.StreamMem();
        stream.set_byte_array(unowned_bytes_array_buffer.to_unowned_byte_array());
        
        return stream;
    }
    
    Memory.UnownedBytesBuffer? unowned_bytes_buffer = buffer as Memory.UnownedBytesBuffer;
    if (unowned_bytes_buffer != null) {
        // StreamMem.with_buffer does do a buffer copy (there's not set_buffer() call like
        // set_byte_array() for some reason), but don't do a buffer copy when it comes out of the
        // Memory.Buffer
        return new GMime.StreamMem.with_buffer(unowned_bytes_buffer.to_unowned_uint8_array());
    }
    
    // do plain-old buffer copy
    return new GMime.StreamMem.with_buffer(buffer.get_uint8_array());
}

public string create_subject_for_reply(Geary.Email email) {
    return (email.subject ?? new Geary.RFC822.Subject("")).create_reply().value;
}

public string create_subject_for_forward(Geary.Email email) {
    return (email.subject ?? new Geary.RFC822.Subject("")).create_forward().value;
}

// Removes address from the list of addresses.  If the list contains only the given address, the
// behavior depends on empty_ok: if true the list will be emptied, otherwise it will leave the
// address in the list once. Used to remove the sender's address from a list of addresses being
// created for the "reply to" recipients.
private void remove_address(Gee.List<Geary.RFC822.MailboxAddress> addresses,
    RFC822.MailboxAddress address, bool empty_ok = false) {
    for (int i = 0; i < addresses.size; ++i) {
        if (addresses[i].equal_to(address) && (empty_ok || addresses.size > 1))
            addresses.remove_at(i--);
    }
}

private bool email_is_from_sender(Geary.Email email, Gee.List<RFC822.MailboxAddress>? sender_addresses) {
    if (sender_addresses == null)
        return false;
    
    return Geary.traverse<RFC822.MailboxAddress>(sender_addresses)
        .any(a => email.from.get_all().contains(a));
}

public Geary.RFC822.MailboxAddresses create_to_addresses_for_reply(Geary.Email email,
    Gee.List< Geary.RFC822.MailboxAddress>? sender_addresses = null) {
    Gee.List<Geary.RFC822.MailboxAddress> new_to =
        new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
    
    // If we're replying to something we sent, send it to the same people we originally did.
    // Otherwise, we'll send to the reply-to address or the from address.
    if (email.to != null && email_is_from_sender(email, sender_addresses))
        new_to.add_all(email.to.get_all());
    else if (email.reply_to != null)
        new_to.add_all(email.reply_to.get_all());
    else if (email.from != null)
        new_to.add_all(email.from.get_all());
    
    // Exclude the current sender.  No need to receive the mail they're sending.
    if (sender_addresses != null) {
        foreach (RFC822.MailboxAddress address in sender_addresses)
            remove_address(new_to, address);
    }
    
    return new Geary.RFC822.MailboxAddresses(new_to);
}

public Geary.RFC822.MailboxAddresses create_cc_addresses_for_reply_all(Geary.Email email,
    Gee.List<Geary.RFC822.MailboxAddress>? sender_addresses = null) {
    Gee.List<Geary.RFC822.MailboxAddress> new_cc = new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
    
    // If we're replying to something we received, also add other recipients.  Don't do this for
    // emails we sent, since everyone we sent it to is already covered in
    // create_to_addresses_for_reply().
    if (email.to != null && !email_is_from_sender(email, sender_addresses))
        new_cc.add_all(email.to.get_all());
    
    if (email.cc != null)
        new_cc.add_all(email.cc.get_all());
    
    // Again, exclude the current sender.
    if (sender_addresses != null) {
        foreach (RFC822.MailboxAddress address in sender_addresses)
            remove_address(new_cc, address, true);
    }
    
    return new Geary.RFC822.MailboxAddresses(new_cc);
}

public Geary.RFC822.MailboxAddresses merge_addresses(Geary.RFC822.MailboxAddresses? first,
    Geary.RFC822.MailboxAddresses? second) {
    Gee.List<Geary.RFC822.MailboxAddress> result = new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
    if (first != null) {
        result.add_all(first.get_all());
        // Add addresses from second that aren't in first.
        if (second != null)
            foreach (Geary.RFC822.MailboxAddress address in second)
                if (!first.contains_normalized(address.address))
                    result.add(address);
    } else if (second != null) {
        result.add_all(second.get_all());
    }
    
    return new Geary.RFC822.MailboxAddresses(result);
}

public Geary.RFC822.MailboxAddresses remove_addresses(Geary.RFC822.MailboxAddresses? from_addresses,
    Geary.RFC822.MailboxAddresses? remove_addresses) {
    Gee.List<Geary.RFC822.MailboxAddress> result = new Gee.ArrayList<Geary.RFC822.MailboxAddress>();
    if (from_addresses != null) {
        result.add_all(from_addresses.get_all());
        if (remove_addresses != null)
            foreach (Geary.RFC822.MailboxAddress address in remove_addresses)
                remove_address(result, address, true);
    }
    return new Geary.RFC822.MailboxAddresses(result);
}

public string reply_references(Geary.Email source) {
    // generate list for References
    Gee.ArrayList<RFC822.MessageID> list = new Gee.ArrayList<RFC822.MessageID>();
    
    // 1. Start with the source's References list
    if (source.references != null && source.references.list.size > 0)
        list.add_all(source.references.list);
    
    // 2. If there are In-Reply-To Message-IDs and they're not in the References list, append them
    if (source.in_reply_to != null) {
        foreach (RFC822.MessageID reply_id in source.in_reply_to.list) {
            if (!list.contains(reply_id))
                list.add(reply_id);
        }
    }
    
    // 3. Append the source's Message-ID, if available.
    if (source.message_id != null)
        list.add(source.message_id);
    
    string[] strings = new string[list.size];
    for(int i = 0; i < list.size; ++i)
        strings[i] = list[i].value;
    
    return (list.size > 0) ? string.joinv(" ", strings) : "";
}

public string email_addresses_for_reply(Geary.RFC822.MailboxAddresses? addresses, TextFormat format) {
    if (addresses == null)
        return "";
    
    switch (format) {
        case TextFormat.HTML:
            return HTML.escape_markup(addresses.to_string());
        
        case TextFormat.PLAIN:
            return addresses.to_string();
        
        default:
            assert_not_reached();
    }
}


/**
 * Returns a quoted text string needed for a reply.
 *
 * If there's no message body in the supplied email or quote text, this
 * function will return the empty string.
 * 
 * If html_format is true, the message will be quoted in HTML format.
 * Otherwise it will be in plain text.
 */
public string quote_email_for_reply(Geary.Email email, string? quote, TextFormat format) {
    if (email.body == null && quote == null)
        return "";
    
    string quoted = (quote == null) ? "<br /><br />" : "";
    
    /// Format for the datetime that a message being replied to was received
    /// See http://developer.gnome.org/glib/2.32/glib-GDateTime.html#g-date-time-format
    string DATE_FORMAT = _("%a, %b %-e, %Y at %-l:%M %p");

    if (email.date != null && email.from != null) {
        /// The quoted header for a message being replied to.
        /// %1$s will be substituted for the date, and %2$s will be substituted for
        /// the original sender.
        string QUOTED_LABEL = _("On %1$s, %2$s wrote:");
        quoted += QUOTED_LABEL.printf(email.date.value.format(DATE_FORMAT),
                                      email_addresses_for_reply(email.from, format));

    } else if (email.from != null) {
        /// The quoted header for a message being replied to (in case the date is not known).
        /// %s will be replaced by the original sender.
        string QUOTED_LABEL = _("%s wrote:");
        quoted += QUOTED_LABEL.printf(email_addresses_for_reply(email.from, format));

    } else if (email.date != null) {
        /// The quoted header for a message being replied to (in case the sender is not known).
        /// %s will be replaced by the original date
        string QUOTED_LABEL = _("On %s:");
        quoted += QUOTED_LABEL.printf(email.date.value.format(DATE_FORMAT));
    }
    
    quoted += "<br />";
    
    quoted += "\n" + quote_body(email, quote, true, format);
    
    if (quote != null)
        quoted += "<br /><br />\n";
    
    return quoted;
}

/**
 * Returns a quoted text string needed for a forward.
 *
 * If there's no message body in the supplied email or quote text, this
 * function will return the empty string.
 *
 * If html_format is true, the message will be quoted in HTML format.
 * Otherwise it will be in plain text.
 */
public string quote_email_for_forward(Geary.Email email, string? quote, TextFormat format) {
    if (email.body == null && quote == null)
        return "";
    
    string quoted = "\n\n";
    
    quoted += _("---------- Forwarded message ----------");
    quoted += "\n\n";
    string from_line = email_addresses_for_reply(email.from, format);
    if (!String.is_empty_or_whitespace(from_line))
        quoted += _("From: %s\n").printf(from_line);
    quoted += _("Subject: %s\n").printf(email.subject != null ? email.subject.to_string() : "");
    quoted += _("Date: %s\n").printf(email.date != null ? email.date.to_string() : "");
    string to_line = email_addresses_for_reply(email.to, format);
    if (!String.is_empty_or_whitespace(to_line))
        quoted += _("To: %s\n").printf(to_line);
    string cc_line = email_addresses_for_reply(email.cc, format);
    if (!String.is_empty_or_whitespace(cc_line))
        quoted += _("Cc: %s\n").printf(cc_line);
    quoted += "\n";  // A blank line between headers and body
    
    quoted = quoted.replace("\n", "<br />");
    
    quoted += quote_body(email, quote, false, format);
    
    return quoted;
}

private string quote_body(Geary.Email email, string? quote, bool use_quotes, TextFormat format) {
    string? body_text = "";
    
    try {
        body_text = quote ?? email.get_message().get_body(format, null);
    } catch (Error error) {
        debug("Could not get message text. %s", error.message);
    }
    
    // Wrap the whole thing in a blockquote.
    if (use_quotes && !String.is_empty(body_text))
        body_text = "<blockquote type=\"cite\">%s</blockquote>".printf(body_text);
    
    return body_text;
}

public bool comp_char_arr_slice(char[] array, uint start, string comp) {
    for (int i = 0; i < comp.length; i++) {
        if (array[start + i] != comp[i])
            return false;
    }
    
    return true;
}

/*
 * This function is adapted from the GMimeFilterBest source in the GMime
 * library (gmime-filter-best.c) by Jeffrey Stedfast, LGPL 2.1.
 *
 * WARNING: This call does not perform async I/O, meaning it will loop on the
 * stream without relinquishing control to the event loop.  Use with
 * caution.
 */
public GMime.ContentEncoding get_best_content_encoding(GMime.Stream stream,
    GMime.EncodingConstraint constraint) {
    int count0 = 0, count8 = 0, linelen = 0, maxline = 0;
    size_t total = 0, readlen;
    // TODO: Increase buffer size?
    uint8[] buffer = new uint8[1024];
    
    while ((readlen = stream.read(buffer)) > 0) {
        total += readlen;
        for(int i = 0; i < readlen; i++) {
            char c = (char) buffer[i];
            if (c == '\n') {
                maxline = maxline > linelen ? maxline : linelen;
                linelen = 0;
            } else {
                linelen++;
                if (c == 0)
                    count0++;
                else if ((c & 0x80) != 0)
                    count8++;
            }
        }
    }
    maxline = maxline > linelen ? maxline : linelen;
    
    GMime.ContentEncoding encoding = GMime.ContentEncoding.DEFAULT;
    switch (constraint) {
        case GMime.EncodingConstraint.7BIT:
            if (count0 > 0) {
                encoding = GMime.ContentEncoding.BASE64;
            } else if (count8 > 0) {
                if (count8 > (int) (total * 0.17))
                    encoding = GMime.ContentEncoding.BASE64;
                else
                    encoding = GMime.ContentEncoding.QUOTEDPRINTABLE;
            } else if (maxline > 998) {
                encoding = GMime.ContentEncoding.QUOTEDPRINTABLE;
            }
        break;
        
        case GMime.EncodingConstraint.8BIT:
            if (count0 > 0)
                encoding = GMime.ContentEncoding.BASE64;
            else if (maxline > 998)
                encoding = GMime.ContentEncoding.QUOTEDPRINTABLE;
        break;
        
        case GMime.EncodingConstraint.BINARY:
            if (count0 + count8 > 0)
                encoding = GMime.ContentEncoding.BINARY;
        break;
    }
    
    return encoding;
}

public string get_clean_attachment_filename(GMime.Part part) {
    string? filename = part.get_filename();
    if (String.is_empty(filename)) {
        /// Placeholder filename for attachments with no filename.
        filename = _("none");
    }
    
    try {
        filename = invalid_filename_character_re.replace_literal(filename, filename.length, 0, "_");
    } catch (RegexError e) {
        debug("Error sanitizing attachment filename: %s", e.message);
    }
    
    return filename;
}

}

