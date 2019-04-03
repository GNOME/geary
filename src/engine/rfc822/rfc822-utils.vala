/* Copyright 2016 Software Freedom Conservancy Inc.
 * Portions copyright (C) 2000-2013 Jeffrey Stedfast
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.RFC822.Utils {

// We use DEL to mark quote levels, since it's unlikely to be in email bodies, is a single byte
// in UTF-8, and is unmolested by GMime.FilterHTML.
public const char QUOTE_MARKER = '\x7f';

/**
 * Charset to use when it is otherwise missing or invalid
 *
 * Per RFC 2045, Section 5.2.
 */
public const string DEFAULT_MIME_CHARSET = "us-ascii";

/**
 * Creates a filter to convert a MIME charset to UTF-8.
 *
 * Param `from_charset` may be null, empty or invalid, in which case
 * `DEFAULT_MIME_CHARSET` will be used instead.
 */
public GMime.FilterCharset create_utf8_filter_charset(string? from_charset) {
    string actual_charset = from_charset != null ? from_charset.strip() : "";
    if (Geary.String.is_empty(actual_charset)) {
        actual_charset = DEFAULT_MIME_CHARSET;
    }
    GMime.FilterCharset? filter_charset = new GMime.FilterCharset(
        actual_charset, Geary.RFC822.UTF8_CHARSET
    );
    if (filter_charset == null) {
        debug("Unknown charset: %s; using RFC 2045 default instead", from_charset);
        filter_charset = new GMime.FilterCharset(
            DEFAULT_MIME_CHARSET, Geary.RFC822.UTF8_CHARSET
        );
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
    if (sender_addresses == null || email.from == null)
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
            return HTML.escape_markup(addresses.to_full_display());

        case TextFormat.PLAIN:
            return addresses.to_full_display();

        default:
            assert_not_reached();
    }
}


public bool comp_char_arr_slice(char[] array, uint start, string comp) {
    for (int i = 0; i < comp.length; i++) {
        if (array[start + i] != comp[i])
            return false;
    }

    return true;
}

/**
 * Obtains the best preview text from a plain or HTML string.
 *
 * The given string `text` should have UNIX encoded line endings (LF),
 * rather than RFC822 (CRLF). The string returned will will have had
 * its whitespace squashed.
 */
public string to_preview_text(string? text, TextFormat format) {
    string preview = "";

    if (format == TextFormat.PLAIN) {
        StringBuilder buf = new StringBuilder();
        string[] all_lines = text.split("\n");
        bool in_inline_pgp_header = false;
        foreach (string line in all_lines) {
            if (in_inline_pgp_header) {
                if (Geary.String.is_empty(line)) {
                    in_inline_pgp_header = false;
                }
                continue;
            }

            if (line.has_prefix("-----BEGIN PGP SIGNED MESSAGE-----")) {
                in_inline_pgp_header = true;
                continue;
            }

            if (line.has_prefix(">"))
                continue;

            if (line.has_prefix("--"))
                continue;

            if (line.has_prefix("===="))
                continue;

            if (line.has_prefix("~~~~"))
                continue;

            if (Geary.String.is_empty_or_whitespace(line)) {
                buf.append("\n");
                continue;
            }

            buf.append(" ");
            buf.append(line);
        }

        preview = buf.str;
    } else if (format == TextFormat.HTML) {
        preview = Geary.HTML.html_to_text(text, false);
    }

    return Geary.String.reduce_whitespace(preview);
}

/**
 * Uses a GMime.FilterBest to determine the best charset.
 *
 * WARNING: This call does not perform async I/O, meaning it will loop on the
 * stream without relinquishing control to the event loop.  Use with
 * caution.
 */
public string get_best_charset(GMime.Stream in_stream) {
    GMime.FilterBest filter = new GMime.FilterBest(
        GMime.FilterBestFlags.CHARSET
    );
    GMime.StreamFilter out_stream = new GMime.StreamFilter(new GMime.StreamNull());
    out_stream.add(filter);
    in_stream.write_to_stream(out_stream);
    in_stream.reset();
    return filter.charset();
}

/**
 * Uses a GMime.FilterBest to determine the best encoding.
 *
 * WARNING: This call does not perform async I/O, meaning it will loop on the
 * stream without relinquishing control to the event loop.  Use with
 * caution.
 */
public GMime.ContentEncoding get_best_encoding(GMime.Stream in_stream) {
    GMime.FilterBest filter = new GMime.FilterBest(
        GMime.FilterBestFlags.ENCODING
    );
    GMime.StreamFilter out_stream = new GMime.StreamFilter(new GMime.StreamNull());
    out_stream.add(filter);
    in_stream.write_to_stream(out_stream);
    in_stream.reset();
    return filter.encoding(GMime.EncodingConstraint.7BIT);
}

}
