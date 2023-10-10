/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2021 Michael Gratton <mike@vee.net>
 * Portions copyright © 2000-2013 Jeffrey Stedfast
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

namespace Geary.RFC822.Utils {

    // We use DEL to mark quote levels, since it's unlikely to be in
    // email bodies, is a single byte in UTF-8, and is unmolested by
    // GMime.FilterHTML.
    public const char QUOTE_MARKER = '\x7f';


    public string create_subject_for_reply(Email email) {
        return (email.subject ?? new Subject("")).create_reply().value;
    }

    public string create_subject_for_forward(Email email) {
        return (email.subject ?? new Subject("")).create_forward().value;
    }

    public MailboxAddresses create_to_addresses_for_reply(Email email,
                                                          Gee.List<MailboxAddress>? sender_addresses = null) {
        var new_to = new Gee.ArrayList<MailboxAddress>();

        if (email.reply_to != null)
            new_to.add_all(email.reply_to.get_all());
        // If we're replying to something we sent, send it to the same people we originally did.
        else if (email.to != null && email_is_from_sender(email, sender_addresses))
            new_to.add_all(email.to.get_all());
        else if (email.from != null)
            new_to.add_all(email.from.get_all());

        // Exclude the current sender.  No need to receive the mail they're sending.
        if (sender_addresses != null) {
            foreach (var address in sender_addresses) {
                remove_address(new_to, address);
            }
        }

        return new MailboxAddresses(new_to);
    }

    public MailboxAddresses create_cc_addresses_for_reply_all(Email email,
                                                              Gee.List<MailboxAddress>? sender_addresses = null) {
        var new_cc = new Gee.ArrayList<MailboxAddress>();

        // If we're replying to something we received, also add other recipients.  Don't do this for
        // emails we sent, since everyone we sent it to is already covered in
        // create_to_addresses_for_reply().
        if (email.to != null && !email_is_from_sender(email, sender_addresses))
            new_cc.add_all(email.to.get_all());

        if (email.from != null)
            new_cc.add_all(email.from.get_all());

        if (email.cc != null)
            new_cc.add_all(email.cc.get_all());

        // Again, exclude the current sender.
        if (sender_addresses != null) {
            foreach (var address in sender_addresses) {
                remove_address(new_cc, address, true);
            }
        }

        return new MailboxAddresses(new_cc);
    }

    public MailboxAddresses merge_addresses(MailboxAddresses? first,
                                            MailboxAddresses? second) {
        var result = new Gee.ArrayList<MailboxAddress>();
        if (first != null) {
            result.add_all(first.get_all());
            // Add addresses from second that aren't in first.
            if (second != null) {
                foreach (MailboxAddress address in second) {
                    if (!first.contains_normalized(address.address))
                        result.add(address);
                }
            }
        } else if (second != null) {
            result.add_all(second.get_all());
        }
        return new MailboxAddresses(result);
    }

    public MailboxAddresses remove_addresses(MailboxAddresses? from_addresses,
                                             MailboxAddresses? remove_addresses) {
        Gee.List<MailboxAddress> result = new Gee.ArrayList<MailboxAddress>();
        if (from_addresses != null) {
            result.add_all(from_addresses.get_all());
            if (remove_addresses != null)
                foreach (MailboxAddress address in remove_addresses)
            remove_address(result, address, true);
        }
        return new MailboxAddresses(result);
    }

    /** Generate a References header value in reply to a message. */
    public MessageIDList reply_references(Email source) {
        var list = new Gee.LinkedList<MessageID>();

        // 1. Start with the source's References list
        if (source.references != null) {
            list.add_all(source.references.get_all());
        }

        // 2. If there are In-Reply-To Message-IDs and they're not in the References list, append them
        if (source.in_reply_to != null) {
            foreach (var reply_id in source.in_reply_to.get_all()) {
                if (!list.contains(reply_id)) {
                    list.add(reply_id);
                }
            }
        }

        // 3. Append the source's Message-ID, if available.
        if (source.message_id != null) {
            list.add(source.message_id);
        }

        return new MessageIDList(list);
    }

    public string email_addresses_for_reply(MailboxAddresses? addresses,
                                            TextFormat format) {
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

        // XXX really shouldn't have to call make_valid here but do so to
        // avoid segfaults in the regex engine on invalid char data. See
        // issue #186 for the proper fix.
        return Geary.String.reduce_whitespace(preview.make_valid());
    }

    /**
     * Decodes RFC-822 long header lines and RFC 2047 encoded text headers.
     */
    internal string decode_rfc822_text_header_value(string rfc822) {
        return GMime.utils_header_decode_text(
            get_parser_options(),
            GMime.utils_header_unfold(rfc822)
        );
    }

    /**
     * Uses a GMime.FilterBest to determine the best charset.
     *
     * This may require processing the entire stream, so occurs in a
     * background thread.
     */
    internal async string get_best_charset(GMime.Stream in_stream,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        GMime.FilterBest filter = new GMime.FilterBest(CHARSET);
        GMime.StreamFilter out_stream = new GMime.StreamFilter(
            new GMime.StreamNull()
        );
        out_stream.add(filter);

        yield Nonblocking.Concurrent.global.schedule_async(() => {
                in_stream.write_to_stream(out_stream);
                in_stream.reset();
                out_stream.close();
            },
            cancellable
        );
        return filter.get_charset();
    }

    /**
     * Uses a GMime.FilterBest to determine the best encoding.
     *
     * This may require processing the entire stream, so occurs in a
     * background thread.
     */
    internal async GMime.ContentEncoding get_best_encoding(GMime.Stream in_stream,
                                                           GMime.EncodingConstraint constraint,
                                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        GMime.FilterBest filter = new GMime.FilterBest(ENCODING);
        GMime.StreamFilter out_stream = new GMime.StreamFilter(
            new GMime.StreamNull()
        );
        out_stream.add(filter);

        yield Nonblocking.Concurrent.global.schedule_async(() => {
                in_stream.write_to_stream(out_stream);
                in_stream.reset();
                out_stream.close();
            },
            cancellable
        );
        return filter.encoding(constraint);
    }

    /**
     * Uses the best-possible transfer of bytes from the Memory.Buffer to the GMime.StreamMem object.
     * The StreamMem object should be destroyed *before* the Memory.Buffer object, since this method
     * will use unowned variants whenever possible.
     */
    internal GMime.StreamMem create_stream_mem(Memory.Buffer buffer) {
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

    internal bool comp_char_arr_slice(uint8[] array, uint start, string comp) {
        for (int i = 0; i < comp.length; i++) {
            if (array[start + i] != comp[i])
                return false;
        }

        return true;
    }

    // Removes address from the list of addresses.  If the list contains only the given address, the
    // behavior depends on empty_ok: if true the list will be emptied, otherwise it will leave the
    // address in the list once. Used to remove the sender's address from a list of addresses being
    // created for the "reply to" recipients.
    private void remove_address(Gee.List<MailboxAddress> addresses,
                                MailboxAddress address,
                                bool empty_ok = false) {
        for (int i = 0; i < addresses.size; ++i) {
            if (addresses[i].equal_to(address) &&
                (empty_ok || addresses.size > 1)) {
                addresses.remove_at(i--);
            }
        }
    }

    private bool email_is_from_sender(Email email, Gee.List<RFC822.MailboxAddress>? sender_addresses) {
        var ret = false;
        if (sender_addresses != null && email.from != null) {
            ret = traverse<MailboxAddress>(sender_addresses)
                .any(a => email.from.get_all().contains(a));
        }
        return ret;
    }

}
