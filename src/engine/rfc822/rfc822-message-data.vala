/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * RFC822.MessageData represents a base class for all the various elements that may be present in
 * an RFC822 message header.  Note that some common elements (such as MailAccount) are not
 * MessageData because they exist in an RFC822 header in list (i.e. multiple email addresses) form.
 */

public interface Geary.RFC822.MessageData : Geary.MessageData.AbstractMessageData {
}

/**
 * An RFC822 Message-ID.
 *
 * MessageID will normalize all strings so that they begin and end with the proper brackets ("<" and
 * ">").
 */
public class Geary.RFC822.MessageID : Geary.MessageData.StringMessageData, Geary.RFC822.MessageData {
    public MessageID(string value) {
        string? normalized = normalize(value);
        base (normalized ?? value);
    }

    // Adds brackets if required, null if no change required
    private static string? normalize(string value) {
        bool needs_prefix = !value.has_prefix("<");
        bool needs_suffix = !value.has_suffix(">");
        if (!needs_prefix && !needs_suffix)
            return null;

        return "%s%s%s".printf(needs_prefix ? "<" : "", value, needs_suffix ? ">" : "");
    }
}

/**
 * A Message-ID list stores its IDs from earliest to latest.
 */
public class Geary.RFC822.MessageIDList : Geary.MessageData.AbstractMessageData, Geary.RFC822.MessageData {
    public Gee.List<MessageID> list { get; private set; }

    public MessageIDList() {
        list = new Gee.ArrayList<MessageID>();
    }

    public MessageIDList.from_collection(Gee.Collection<MessageID> collection) {
        this ();

        foreach(MessageID msg_id in collection)
            this.list.add(msg_id);
    }

    public MessageIDList.single(MessageID msg_id) {
        this ();

        list.add(msg_id);
    }

    public MessageIDList.from_rfc822_string(string value) {
        this ();

        // Have seen some mailers use commas between Message-IDs and whitespace inside Message-IDs,
        // meaning that the standard whitespace tokenizer is not sufficient.  The only guarantee
        // made of a Message-ID is that it's surrounded by angle brackets, so save anything inside
        // angle brackets
        //
        // NOTE: Seen at least one spamfilter mailer that imaginatively uses parens instead of
        // angle brackets for its Message-IDs; accounting for that as well here.  The addt'l logic
        // is to allow open-parens inside a Message-ID and not treat it as a delimiter; if a
        // close-parens is found, that's a problem (but isn't expected)
        //
        // Also note that this parser will attempt to parse Message-IDs lacking brackets.  If one
        // is found, then it will assume all remaining Message-IDs in the list are bracketed and
        // be a little less liberal in its parsing.
        StringBuilder canonicalized = new StringBuilder();
        int index = 0;
        char ch;
        bool in_message_id = false;
        bool bracketed = false;
        while (Ascii.get_next_char(value, ref index, out ch)) {
            bool add_char = false;
            switch (ch) {
                case '<':
                    in_message_id = true;
                    bracketed = true;
                break;

                case '(':
                    if (!in_message_id) {
                        in_message_id = true;
                        bracketed = true;
                    } else {
                        add_char = true;
                    }
                break;

                case '>':
                    in_message_id = false;
                break;

                case ')':
                    if (in_message_id)
                        in_message_id = false;
                    else
                        add_char = true;
                break;

                default:
                    // deal with Message-IDs without brackets ... bracketed is set to true the
                    // moment the first one is found, so this doesn't deal with combinations of
                    // bracketed and unbracketed text ... MessageID's ctor will deal with adding
                    // brackets to unbracketed id's
                    if (!bracketed) {
                        if (!in_message_id && !ch.isspace())
                            in_message_id = true;
                        else if (in_message_id && ch.isspace())
                            in_message_id = false;
                    }

                    // only add characters inside the brackets or, if not bracketed, work around
                    add_char = in_message_id;
                break;
            }

            if (add_char)
                canonicalized.append_c(ch);

            if (!in_message_id && !String.is_empty(canonicalized.str)) {
                list.add(new MessageID(canonicalized.str));

                canonicalized = new StringBuilder();
            }
        }

        // pick up anything that doesn't end with brackets
        if (!String.is_empty(canonicalized.str))
            list.add(new MessageID(canonicalized.str));

        // don't assert that list.size > 0; even though this method should generated a decoded ID
        // from any non-empty string, an empty Message-ID (i.e. "<>") won't.
    }

    /**
     * Returns a new list with the given messages ids appended to this list's.
     */
    public MessageIDList append(MessageIDList others) {
        MessageIDList new_ids = new MessageIDList();
        new_ids.list.add_all(this.list);
        new_ids.list.add_all(others.list);
        return new_ids;
    }

    public override string to_string() {
        return "MessageIDList (%d)".printf(list.size);
    }

    public virtual string to_rfc822_string() {
        string[] strings = new string[list.size];
        for(int i = 0; i < list.size; ++i)
            strings[i] = list[i].value;

        return string.joinv(" ", strings);
    }
}

public class Geary.RFC822.Date : Geary.RFC822.MessageData, Geary.MessageData.AbstractMessageData,
    Gee.Hashable<Geary.RFC822.Date> {

    public string? original { get; private set; }
    public DateTime value { get; private set; }

    public Date(string rfc822) throws ImapError {
        int offset = 0;
        int64 time_t_utc = GMime.utils_header_decode_date(rfc822, out offset);
        if (time_t_utc == 0)
            throw new ImapError.PARSE_ERROR(
                "Unable to parse \"%s\": Not ISO-8601 date", rfc822
            );

        DateTime? value = new DateTime.from_unix_utc(time_t_utc);
        if (value == null) {
            throw new ImapError.PARSE_ERROR(
                "Unable to parse \"%s\": Outside supported range", rfc822
            );
        }
        this.value = value;

        if (offset != 0) {
            this.value = value.to_timezone(
                new GLib.TimeZone("%+05d".printf(offset))
            );
        }

        this.original = rfc822;
    }

    public Date.from_date_time(DateTime datetime) {
        this.original = null;
        this.value = datetime;
    }

    /**
     * Returns the {@link Date} in RFC 822 format.
     */
    public string to_rfc822_string() {
        // Although GMime documents its conversion methods as
        // requiring the tz offset in hours, it appears the number is
        // handed directly to the string (i.e. an offset of -7:30 becomes
        // "-0007", whereas we want "-0730").
        int hours = (int) GLib.Math.floor(value.get_utc_offset() / TimeSpan.HOUR);
        int minutes = (int) (
            (value.get_utc_offset() % TimeSpan.HOUR) / (double) TimeSpan.HOUR * 60
        );
        return GMime.utils_header_format_date(
            (time_t) this.value.to_utc().to_unix(),
            (hours * 100) + minutes
        );
    }

    /**
     * Returns {@link Date} for transmission.
     *
     * @see to_rfc822_string
     */
    public virtual string serialize() {
        return to_rfc822_string();
    }

    public virtual bool equal_to(Geary.RFC822.Date other) {
        return (this != other) ? value.equal(other.value) : true;
    }

    public virtual uint hash() {
        return value.hash();
    }

    public override string to_string() {
        return original ?? value.to_string();
    }
}

public class Geary.RFC822.Size : Geary.MessageData.Int64MessageData, Geary.RFC822.MessageData {
    public Size(int64 value) {
        base (value);
    }
}

public class Geary.RFC822.Subject : Geary.MessageData.StringMessageData,
    Geary.MessageData.SearchableMessageData, Geary.RFC822.MessageData {
    public const string REPLY_PREFACE = "Re:";
    public const string FORWARD_PREFACE = "Fwd:";

    public string original { get; private set; }

    public Subject(string value) {
        base (value);
        original = value;
    }

    public Subject.decode(string value) {
        base (GMime.utils_header_decode_text(value));
        original = value;
    }

    public bool is_reply() {
        return value.down().has_prefix(REPLY_PREFACE.down());
    }

    public Subject create_reply() {
        return is_reply() ? new Subject(value) : new Subject("%s %s".printf(REPLY_PREFACE,
            value));
    }

    public bool is_forward() {
        return value.down().has_prefix(FORWARD_PREFACE.down());
    }

    public Subject create_forward() {
        return is_forward() ? new Subject(value) : new Subject("%s %s".printf(FORWARD_PREFACE,
            value));
    }

    /**
     * Returns the Subject: line stripped of reply and forwarding prefixes.
     *
     * Strips ''all'' prefixes, meaning "Re: Fwd: Soup's on!" will return "Soup's on!"
     *
     * Returns an empty string if the Subject: line is empty (or is empty after stripping prefixes).
     */
    public string strip_prefixes() {
        string subject_base = value;
        bool changed = false;
        do {
            string stripped;
            try {
                Regex re_regex = new Regex("^(?i:Re:\\s*)+");
                stripped = re_regex.replace(subject_base, -1, 0, "");

                Regex fwd_regex = new Regex("^(?i:Fwd:\\s*)+");
                stripped = fwd_regex.replace(stripped, -1, 0, "");
            } catch (RegexError e) {
                debug("Failed to clean up subject line \"%s\": %s", value, e.message);

                break;
            }

            changed = (stripped != subject_base);
            if (changed)
                subject_base = stripped;
        } while (changed);

        return String.reduce_whitespace(subject_base);
    }

    /**
     * See Geary.MessageData.SearchableMessageData.
     */
    public string to_searchable_string() {
        return value;
    }
}

public class Geary.RFC822.Header : Geary.MessageData.BlockMessageData, Geary.RFC822.MessageData {
    private GMime.Message? message = null;
    private string[]? names = null;

    public Header(Memory.Buffer buffer) {
        base ("RFC822.Header", buffer);
    }

    private unowned GMime.HeaderList get_headers() throws RFC822Error {
        if (message != null)
            return message.get_header_list();

        GMime.Parser parser = new GMime.Parser.with_stream(Utils.create_stream_mem(buffer));
        parser.set_respect_content_length(false);
        parser.set_scan_from(false);

        message = parser.construct_message();
        if (message == null)
            throw new RFC822Error.INVALID("Unable to parse RFC 822 headers");

        return message.get_header_list();
    }

    public string? get_header(string name) throws RFC822Error {
        return get_headers().get(name);
    }

    public string[] get_header_names() throws RFC822Error {
        if (names != null)
            return names;

        names = new string[0];

        unowned GMime.HeaderIter iter;
        if (!get_headers().get_iter(out iter))
            return names;

        do {
            names += iter.get_name();
        } while (iter.next());

        return names;
    }
}

public class Geary.RFC822.Text : Geary.MessageData.BlockMessageData, Geary.RFC822.MessageData {
    public Text(Memory.Buffer buffer) {
        base ("RFC822.Text", buffer);
    }
}

public class Geary.RFC822.Full : Geary.MessageData.BlockMessageData, Geary.RFC822.MessageData {
    public Full(Memory.Buffer buffer) {
        base ("RFC822.Full", buffer);
    }
}

// Used for decoding preview text.
public class Geary.RFC822.PreviewText : Geary.RFC822.Text {
    public PreviewText(Memory.Buffer _buffer) {
        base (_buffer);
    }

    public PreviewText.with_header(Memory.Buffer preview_header, Memory.Buffer preview) {
        string preview_text = "";

        // Parse the header.
        GMime.Stream header_stream = Utils.create_stream_mem(preview_header);
        GMime.Parser parser = new GMime.Parser.with_stream(header_stream);
        GMime.Part? gpart = parser.construct_part() as GMime.Part;
        if (gpart != null) {
            Part part = new Part(gpart);

            Mime.ContentType content_type = part.content_type;
            bool is_plain = content_type.is_type("text", "plain");
            bool is_html = content_type.is_type("text", "html");

            if (is_plain || is_html) {
                // Parse the partial body
                GMime.DataWrapper body = new GMime.DataWrapper.with_stream(
                    new GMime.StreamMem.with_buffer(preview.get_uint8_array()),
                    gpart.get_content_encoding()
                );
                gpart.set_content_object(body);

                ByteArray output = new ByteArray();
                GMime.StreamMem output_stream =
                    new GMime.StreamMem.with_byte_array(output);
                output_stream.set_owner(false);

                try {
                    part.write_to_stream(
                        output_stream, Part.EncodingConversion.NONE
                    );
                    uint8[] data = output.data;
                    data += (uint8) '\0';

                    preview_text = Geary.RFC822.Utils.to_preview_text(
                        (string) data,
                        is_html ? TextFormat.HTML : TextFormat.PLAIN
                    );
                } catch (RFC822Error err) {
                    debug("Failed to parse preview body: %s", err.message);
                }
            }
        }

        base(new Geary.Memory.StringBuffer(preview_text));
    }

    public PreviewText.from_string(string preview) {
        base (new Geary.Memory.StringBuffer(preview));
    }
}
