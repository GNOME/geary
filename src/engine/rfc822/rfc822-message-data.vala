/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020-2021 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A base interface for objects that represent decoded RFC822 headers.
 *
 * The value of these objects is the decoded form of the header
 * data. Encoded forms can be obtained via {@link to_rfc822_string}.
 */
public interface Geary.RFC822.DecodedMessageData :
    Geary.MessageData.AbstractMessageData {

    /** Returns an RFC822-safe string representation of the data. */
    public abstract string to_rfc822_string();

}

/**
 * A base interface for objects that represent encoded RFC822 header data.
 *
 * The value of these objects is the RFC822 encoded form of the header
 * data. Decoded forms can be obtained via means specific to
 * implementations of this interface.
 */
public interface Geary.RFC822.EncodedMessageData :
    Geary.MessageData.BlockMessageData {

}

/**
 * A RFC822 Message-ID.
 *
 * The decoded form of the id is the `addr-spec` portion, that is,
 * without the leading `<` and tailing `>`.
 */
public class Geary.RFC822.MessageID :
    Geary.MessageData.StringMessageData, DecodedMessageData {

    public MessageID(string value) {
        base(value);
    }

    public MessageID.from_rfc822_string(string rfc822) throws Error {
        int len = rfc822.length;
        int start = 0;
        while (start < len && rfc822[start].isspace()) {
            start += 1;
        }
        char end_delim = 0;
        bool break_on_space = false;
        if (start < len) {
            switch (rfc822[start]) {
            case '<':
                // Standard delim
                start += 1;
                end_delim = '>';
                break;

            case '(':
                // Non-standard delim
                start += 1;
                end_delim = ')';
                break;

            default:
                // no other supported delimiters, so just end at white
                // space or EOS
                break_on_space = true;
                break;
            }
        }
        int end = start + 1;
        while (end < len &&
               rfc822[end] != end_delim &&
               (!break_on_space || !rfc822[end].isspace())) {
            end += 1;
        }

        if (start + 1 >= end) {
            throw new Error.INVALID("Empty RFC822 message id");
        }
        base(rfc822.slice(start, end));
    }

    /**
     * Returns the {@link Date} in RFC 822 format.
     */
    public string to_rfc822_string() {
        return "<%s>".printf(this.value);
    }

}


/**
 * A immutable list of RFC822 Message-ID values.
 */
public class Geary.RFC822.MessageIDList :
    Geary.MessageData.AbstractMessageData,
    DecodedMessageData {


    /** Returns the number of ids in this list. */
    public int size {
        get { return this.list.size; }
    }

    /** Determines if there are no ids in the list. */
    public bool is_empty {
        get { return this.list.is_empty; }
    }

    private Gee.List<MessageID> list = new Gee.ArrayList<MessageID>();


    /**
     * Constructs a new Message-Id list.
     *
     * If the optional collection of ids is not given, the list
     * is created empty. Otherwise the collection's ids are
     * added to the list by iterating over it in natural order.
     */
    public MessageIDList(Gee.Collection<MessageID>? collection = null) {
        if (collection != null) {
            this.list.add_all(collection);
        }
    }

    /** Constructs a new Message-Id list containing a single id. */
    public MessageIDList.single(MessageID msg_id){
        this();
        list.add(msg_id);
    }

    /** Constructs a new Message-Id list by parsing a RFC822 string. */
    public MessageIDList.from_rfc822_string(string rfc822)
        throws Error {
        this();

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
        while (Ascii.get_next_char(rfc822, ref index, out ch)) {
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

        if (this.list.is_empty) {
            throw new Error.INVALID("Empty RFC822 message id list: %s", rfc822);
        }
    }

    /** Returns the id at the given index, if it exists. */
    public new MessageID? get(int index) {
        return this.list.get(index);
    }

    /** Returns a read-only iterator of the ids in this list. */
    public Gee.Iterator<MessageID> iterator() {
        return this.list.read_only_view.iterator();
    }

    /** Returns a read-only collection of the ids in this list. */
    public Gee.List<MessageID> get_all() {
        return this.list.read_only_view;
    }

    /**
     * Returns a list with the given id appended if not already present.
     *
     * This list is returned if the given id is already present,
     * otherwise the result of a call to {@link concatenate_id} is
     * returned.
     */
    public MessageIDList merge_id(MessageID other) {
        return this.list.contains(other) ? this : this.concatenate_id(other);
    }

    /**
     * Returns a list with the given ids appended if not already present.
     *
     * This list is returned if all given ids are already present,
     * otherwise the result of a call to {@link concatenate_id} for
     * each not present is returned.
     */
    public MessageIDList merge_list(MessageIDList other) {
        var list = this;
        foreach (var id in other) {
            if (!this.list.contains(id)) {
                list = list.concatenate_id(id);
            }
        }
        return list;
    }

    /**
     * Returns a new list with the given list appended to this.
     */
    public MessageIDList concatenate_id(MessageID other) {
        var new_ids = new MessageIDList(this.list);
        new_ids.list.add(other);
        return new_ids;
    }

    /**
     * Returns a new list with the given list appended to this.
     */
    public MessageIDList concatenate_list(MessageIDList others) {
        var new_ids = new MessageIDList(this.list);
        new_ids.list.add_all(others.list);
        return new_ids;
    }

    public override string to_string() {
        return "MessageIDList (%d)".printf(list.size);
    }

    public string to_rfc822_string() {
        string[] strings = new string[list.size];
        for (int i = 0; i < this.list.size; ++i) {
            strings[i] = this.list[i].to_rfc822_string();
        }

        return string.joinv(" ", strings);
    }

}

public class Geary.RFC822.Date :
    Geary.MessageData.AbstractMessageData,
    Gee.Hashable<Geary.RFC822.Date>,
    DecodedMessageData {


    public GLib.DateTime value { get; private set; }

    private string? rfc822;


    public Date(GLib.DateTime datetime) {
        this.value = datetime;
        this.rfc822 = null;
    }

    public Date.from_rfc822_string(string rfc822) throws Error {
        var date = GMime.utils_header_decode_date(rfc822);
        if (date == null) {
            throw new Error.INVALID("Not ISO-8601 date: %s", rfc822);
        }
        this.rfc822 = rfc822;
        this.value = date;
    }

    /**
     * Returns the {@link Date} in RFC 822 format.
     */
    public string to_rfc822_string() {
        if (this.rfc822 == null) {
            this.rfc822 = GMime.utils_header_format_date(this.value);
        }
        return this.rfc822;
    }

    public virtual bool equal_to(Geary.RFC822.Date other) {
        return this == other || this.value.equal(other.value);
    }

    public virtual uint hash() {
        return this.value.hash();
    }

    public override string to_string() {
        return this.value.to_string();
    }

}

public class Geary.RFC822.Subject :
    Geary.MessageData.StringMessageData,
    Geary.MessageData.SearchableMessageData,
    DecodedMessageData {

    public const string REPLY_PREFACE = "Re:";
    public const string FORWARD_PREFACE = "Fwd:";


    private string rfc822;


    public Subject(string value) {
        base(value);
        this.rfc822 = null;
    }

    public Subject.from_rfc822_string(string rfc822) {
        base(Utils.decode_rfc822_text_header_value(rfc822));
        this.rfc822 = rfc822;
    }

    /**
     * Returns the subject line encoded for an RFC 822 message.
     */
    public string to_rfc822_string() {
        if (this.rfc822 == null) {
            this.rfc822 = GMime.utils_header_encode_text(
                get_format_options(), this.value, null
            );
        }
        return this.rfc822;
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

public class Geary.RFC822.Header :
    Geary.MessageData.BlockMessageData, EncodedMessageData {


    private GMime.HeaderList headers;
    private string[]? names = null;


    // The ctors for this class seem the wrong way around, but the
    // default accepts a memory buffer and not a GMime.HeaderList to
    // keep it consistent with other EncodedMessageData
    // implementations.

    public Header(Memory.Buffer buffer) throws Error {
        base("RFC822.Header", buffer);

        var parser = new GMime.Parser.with_stream(
            Utils.create_stream_mem(buffer)
        );
        parser.set_respect_content_length(false);
        parser.set_format(MESSAGE);

        var message = parser.construct_message(null);
        if (message == null) {
            throw new Error.INVALID("Unable to parse RFC 822 headers");
        }

        this.headers = message.get_header_list();
    }

    public Header.from_gmime(GMime.Object gmime) {
        base(
            "RFC822.Header",
            new Memory.StringBuffer(gmime.get_headers(get_format_options()))
        );
        this.headers = gmime.get_header_list();
    }

    public string? get_header(string name) {
        string? value = null;
        var header = this.headers.get_header(name);
        if (header != null) {
            value = header.get_value();
        }
        return value;
    }

    public string? get_raw_header(string name) {
        string? value = null;
        var header = this.headers.get_header(name);
        if (header != null) {
            value = header.get_raw_value();
        }
        return value;
    }

    public string[] get_header_names() {
        if (this.names == null) {
            var names = new string[this.headers.get_count()];
            for (int i = 0; i < names.length; i++) {
                names[i] = this.headers.get_header_at(i).get_name();
            }
            this.names = names;
        }
        return this.names;
    }

}

public class Geary.RFC822.Text :
    Geary.MessageData.BlockMessageData, EncodedMessageData {


    private class GMimeBuffer : Memory.Buffer, Memory.UnownedBytesBuffer {


        public override size_t allocated_size {
            get { return (size_t) this.stream.length; }
        }

        public override size_t size {
            get { return (size_t) this.stream.length; }
        }

        private GMime.Stream stream;
        private GLib.Bytes buf = null;

        public GMimeBuffer(GMime.Stream stream) {
            this.stream = stream;
        }

        public override GLib.Bytes get_bytes() {
            if (this.buf == null) {
                this.stream.seek(0, SET);
                uint8[] bytes = new uint8[this.stream.length()];
                this.stream.read(bytes);
                this.buf = new GLib.Bytes.take(bytes);
            }
            return this.buf;
        }

        public unowned uint8[] to_unowned_uint8_array() {
            return get_bytes().get_data();
        }

    }

    public Text(Memory.Buffer buffer) {
        base("RFC822.Text", buffer);
    }

    public Text.from_gmime(GMime.Stream gmime) {
        base("RFC822.Text", new GMimeBuffer(gmime));
    }

}

public class Geary.RFC822.Full :
    Geary.MessageData.BlockMessageData, EncodedMessageData {

    public Full(Memory.Buffer buffer) {
        base("RFC822.Full", buffer);
    }

}

/** Represents text providing a preview of an email's body. */
public class Geary.RFC822.PreviewText : Geary.RFC822.Text {

    public PreviewText(Memory.Buffer _buffer) {
        base (_buffer);
    }

    public PreviewText.with_header(Memory.Buffer preview_header, Memory.Buffer preview) {
        string preview_text = "";

        // Parse the header.
        GMime.Stream header_stream = Utils.create_stream_mem(preview_header);
        GMime.Parser parser = new GMime.Parser.with_stream(header_stream);
        GMime.Part? gpart = parser.construct_part(Geary.RFC822.get_parser_options()) as GMime.Part;
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
                gpart.set_content(body);

                try {
                    Memory.Buffer preview_buffer = part.write_to_buffer(
                        Part.EncodingConversion.UTF8
                    );
                    preview_text = Geary.RFC822.Utils.to_preview_text(
                        preview_buffer.get_valid_utf8(),
                        is_html ? TextFormat.HTML : TextFormat.PLAIN
                    );
                } catch (Error err) {
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

public class Geary.RFC822.AuthenticationResults :
    Geary.MessageData.StringMessageData {

    public AuthenticationResults(string value) {
        base(value);
    }

    /**
     * Returns the authentication result for dkim.
     */
    public bool is_dkim_valid() {
        return /^.*dkim=pass.*$/i.match(this.value);
    }

     /**
     * Returns the authentication result for dmarc.
     */
    public bool is_dmarc_valid() {
        return /^.*dmarc=pass.*$/i.match(this.value);
    }
}
