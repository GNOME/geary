/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A symbolic representation of IMAP FETCH's BODY section parameter.
 *
 * This is only used with {@link FetchCommand}.  Most IMAP FETCH calls can be achieved with
 * plain {@link FetchDataSpecifier}s.  Some cannot, however, and this more complicated
 * specifier must be used.
 *
 * A fully-qualified specifier looks something like this for requests:
 *
 * BODY[part_number.section_part]<subset_start.subset_count>
 *
 * or, when headers are specified:
 *
 * BODY[part_number.section_part (header_fields)]<subset_start.subset_count>
 *
 * There is also a .peek variant.
 *
 * For responses, a fully-qualified specifier looks something like this:
 *
 * BODY[part_number.section_part (header_fields)]<subset_start>
 *
 * There is no .peek variant in responses.
 *
 * Note that Gmail apparently doesn't like BODY[1.TEXT] and instead must be specified with
 * BODY[1].  Also note that there's a PEEK variant that will not add the /Seen flag to the message.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.5]], specifically section on
 * BODY[<section>]<<partial>>, and [[http://tools.ietf.org/html/rfc3501#section-7.4.2]],
 * specifically section on BODY[<section>]<<origin octet>>.
 *
 * @see FetchDataSpecifier
 */

public class Geary.Imap.FetchBodyDataSpecifier : BaseObject, Gee.Hashable<FetchBodyDataSpecifier> {
    /**
     * Specifies which section (or partial section) is being requested with this identifier.
     */
    public enum SectionPart {
        NONE,
        HEADER,
        HEADER_FIELDS,
        HEADER_FIELDS_NOT,
        MIME,
        TEXT;

        public string serialize() {
            switch (this) {
                case NONE:
                    return "";

                case HEADER:
                    return "header";

                case HEADER_FIELDS:
                    return "header.fields";

                case HEADER_FIELDS_NOT:
                    return "header.fields.not";

                case MIME:
                    return "mime";

                case TEXT:
                    return "text";

                default:
                    assert_not_reached();
            }
        }

        public static SectionPart deserialize(string value) throws ImapError {
            if (String.is_empty(value))
                return NONE;

            switch (Ascii.strdown(value)) {
                case "header":
                    return HEADER;

                case "header.fields":
                    return HEADER_FIELDS;

                case "header.fields.not":
                    return HEADER_FIELDS_NOT;

                case "mime":
                    return MIME;

                case "text":
                    return TEXT;

                default:
                    throw new ImapError.PARSE_ERROR("Invalid SectionPart name \"%s\"", value);
            }
        }

        public string to_string() {
            return serialize();
        }
    }

    /**
     * The {@link SectionPart} for this FETCH BODY specifier.
     *
     * This is exposed to detect a server bug; other fields in this object could be exposed as
     * well in the future, if necessary.
     */
    public SectionPart section_part { get; private set; }

    /**
     * When false, indicates that the FETCH BODY specifier is using a hack to operate with
     * non-conformant servers.
     *
     * This is exposed to detect a server bug; other fields in this object could be exposed as
     * well in the future, if necessary.
     *
     * @see omit_request_header_fields_space
     */
    public bool request_header_fields_space { get; private set; default = true; }

    private int[]? part_number;
    private int subset_start;
    private int subset_count;
    private Gee.TreeSet<string>? field_names;
    private bool is_peek;
    private string hashable;

    /**
     * Create a FetchBodyDataType with the various required and optional parameters specified.
     *
     * Set part_number to null to ignore.  Set subset_start less than zero to ignore.
     * subset_count must be greater than zero if subset_start is greater than zero.
     *
     * field_names are required for {@link SectionPart.HEADER_FIELDS} and
     * {@link SectionPart.HEADER_FIELDS_NOT} and must be null for all other {@link SectionPart}s.
     */
    public FetchBodyDataSpecifier(SectionPart section_part, int[]? part_number, int subset_start,
        int subset_count, string[]? field_names) {
        init(section_part, part_number, subset_start, subset_count, field_names, false, false);
    }

    /**
     * Like FetchBodyDataType, but the /Seen flag will not be set when used on a message.
     */
    public FetchBodyDataSpecifier.peek(SectionPart section_part, int[]? part_number, int subset_start,
        int subset_count, string[]? field_names) {
        init(section_part, part_number, subset_start, subset_count, field_names, true, false);
    }

    public FetchBodyDataSpecifier.response(SectionPart section_part, int[]? part_number,
        int subset_start, string[]? field_names) {
        init(section_part, part_number, subset_start, -1, field_names, false, true);
    }

    private void init(SectionPart section_part, int[]? part_number, int subset_start, int subset_count,
        string[]? field_names, bool is_peek, bool is_response) {
        switch (section_part) {
            case SectionPart.HEADER_FIELDS:
            case SectionPart.HEADER_FIELDS_NOT:
                assert(field_names != null && field_names.length > 0);
            break;

            default:
                assert(field_names == null);
            break;
        }

        if (subset_start >= 0 && !is_response)
            assert(subset_count > 0);

        this.section_part = section_part;
        this.part_number = part_number;
        this.subset_start = subset_start;
        this.subset_count = subset_count;
        this.is_peek = is_peek;

        if (field_names != null && field_names.length > 0) {
            this.field_names = new Gee.TreeSet<string>(Ascii.strcmp);
            foreach (string field_name in field_names) {
                string converted = Ascii.strdown(field_name.strip());

                if (!String.is_empty(converted))
                    this.field_names.add(converted);
            }
        } else {
            this.field_names = null;
        }

        // see equal_to() for why the response version is used
        hashable = serialize_response();
    }

    /**
     * Returns the {@link FetchBodyDataSpecifier} in a string ready for a {@link Command}.
     *
     * The serialized field names are returned in a case-insensitive casefolded order.
     * (Some servers return field names in arbitrary order.)
     */
    public string serialize_request() {
        return (!is_peek ? "body[%s%s%s]%s" : "body.peek[%s%s%s]%s").printf(
            serialize_part_number(),
            section_part.serialize(),
            serialize_field_names(),
            serialize_subset(true));
    }

    /**
     * Returns the {@link FetchBodyDataSpecifier} in a string as it might appear in a
     * {@link ServerResponse}.
     *
     * The FetchBodyDataType server response does not include the peek modifier or the span
     * length if a span was indicated (as the following literal specifies its length).
     *
     * The serialized field names are returned in a case-insensitive casefolded order.
     * (Some servers return field names in arbitrary order.)
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.4.2]]
     */
    internal string serialize_response() {
        return "body[%s%s%s]%s".printf(
            serialize_part_number(),
            section_part.serialize(),
            serialize_field_names(),
            serialize_subset(false));
    }

    public Parameter to_request_parameter() {
        return new AtomParameter(serialize_request());
    }

    private string serialize_part_number() {
        if (part_number == null || part_number.length == 0)
            return "";

        StringBuilder builder = new StringBuilder();
        foreach (int part in part_number) {
            if (builder.len > 0)
                builder.append_c('.');

            builder.append_printf("%d", part);
        }

        // if there's a SectionPart that follows, append a period as a separator
        if (section_part != SectionPart.NONE)
            builder.append_c('.');

        return builder.str;
    }

    private string serialize_field_names() {
        if (field_names == null || field_names.size == 0)
            return "";

        // note that the leading space is supplied here
        StringBuilder builder = new StringBuilder(request_header_fields_space ? " (" : "(");
        Gee.Iterator<string> iter = field_names.iterator();
        while (iter.next()) {
            builder.append(iter.get());
            if (iter.has_next())
                builder.append_c(' ');
        }
        builder.append_c(')');

        return builder.str;
    }

    // See note at serialize_response for reason is_request is necessary.
    // Note that this could've been formed with the .response() ctor, which doesn't pass along
    // subset_count (because it's unknown), so this simply uses subset_start in that case
    private string serialize_subset(bool is_request) {
        if (is_request && subset_count >= 0)
            return (subset_start < 0) ? "" : "<%d.%d>".printf(subset_start, subset_count);
        else
            return (subset_start < 0) ? "" : "<%d>".printf(subset_start);
    }

    /**
     * Returns true if the {@link StringParameter} is formatted like a
     * {@link FetchBodyDataSpecifier}.
     *
     * This method doesn't do a //full// test.  It's possible for {@link deserialize_response} to
     * throw an exception if this method returns true.  This method should be used for simple
     * identification when parsing and then catch the exception as the final word on validity.
     *
     * @see deserialize_response
     */
    public static bool is_fetch_body_data_specifier(StringParameter stringp) {
        string strd = stringp.as_lower().strip();

        return strd.has_prefix("body[") || strd.has_prefix("body.peek[");
    }

    /**
     * Attempts to convert a {@link StringParameter} into a {@link FetchBodyDataSpecifier}.
     *
     * This will ''only'' convert responses from an IMAP server.  The request version of the
     * specifier has optional parameters not parsed here.  There currently is no
     * deserialize_request() version of this method.
     *
     * If any portion of the StringParameter doesn't look like a FETCH BODY data specifier,
     * an {@link ImapError.PARSE_ERROR} is thrown.
     */
    public static FetchBodyDataSpecifier deserialize_response(StringParameter stringp) throws ImapError {
        // * case-insensitive
        // * leading/trailing whitespace stripped
        // * Remove quoting (some servers return field names quoted, some don't, Geary never uses them
        //   when requesting)
        string strd = stringp.as_lower().replace("\"", "").strip();

        // Convert full form into two sections: "body[SECTION_STRING]<OCTET_STRING>"
        //                                                           ^^^^^^^^^^^^^^ optional
        // response never contains ".peek", even if specified in request
        unowned string section_string;
        unowned string? octet_string;
        char[] section_chars = new char[strd.length];
        char[]? octet_chars = new char[strd.length];
        int count;
        switch (count = strd.scanf("body[%[^]]]%s", section_chars, octet_chars)) {
            case 1:
                // no octet-string specified
                section_string = (string) section_chars;
                octet_string = null;
            break;

            case 2:
                section_string = (string) section_chars;
                octet_string = (string) octet_chars;
            break;

            default:
                throw new ImapError.PARSE_ERROR("%s is not a FETCH body data type %d", stringp.to_string(),
                    count);
        }

        // convert section string into its parts:
        // "PART_STRING (FIELDS_STRING)"
        //             ^^^^^^^^^^^^^^^^ optional
        char[] part_chars = new char[section_string.length];
        char[] fields_chars = new char[section_string.length];
        unowned string part_string;
        unowned string? fields_string;
        if (section_string.contains("(")) {
            if (section_string.scanf("%[^(](%[^)])", part_chars, fields_chars) != 2)
                throw new ImapError.PARSE_ERROR("%s: malformed part/header names", stringp.to_string());

            part_string = (string) part_chars;
            fields_string = (string?) fields_chars;
        } else {
            part_string = section_string;
            fields_string = null;
        }

        // convert part_string into its part number and section part name
        // "#.#.#.SECTION_PART"
        //  ^^^^^^ optional
        StringBuilder section_part_builder = new StringBuilder();
        int[]? part_number = null;
        string[]? part_number_tokens = part_string.split(".");
        if (part_number_tokens != null) {
            bool no_more = false;
            for (int ctr = 0; ctr < part_number_tokens.length; ctr++) {
                string token = part_number_tokens[ctr];

                // stop treating as numbers when non-digit found (SectionParts contain periods
                // too and must be preserved);
                if (!no_more && Ascii.is_numeric(token)) {
                    if (part_number == null)
                        part_number = new int[0];

                    part_number += int.parse(token);
                } else {
                    no_more = true;
                    section_part_builder.append(token);
                    if (ctr < (part_number_tokens.length - 1))
                        section_part_builder.append(".");
                }
            }
        } else {
            section_part_builder.append(part_string);
        }

        SectionPart section_part = SectionPart.deserialize(section_part_builder.str.strip());

        // Convert optional fields_string into an array of field names
        string[]? field_names = null;
        if (fields_string != null) {
            field_names = fields_string.strip().split(" ");
            if (field_names.length == 0)
                field_names = null;
        }

        // If octet_string found, trim surrounding brackets and convert to integer
        // The span in the returned response is merely the offset ("1.15" becomes "1") because the
        // associated literal data specifies its own length)
        int subset_start = -1;
        if (!String.is_empty(octet_string)) {
            if (octet_string.scanf("<%d>", out subset_start) != 1) {
                throw new ImapError.PARSE_ERROR("Improperly formed octet \"%s\" in %s", octet_string,
                    stringp.to_string());
            }

            if (subset_start < 0) {
                throw new ImapError.PARSE_ERROR("Invalid octet count %d in %s", subset_start,
                    stringp.to_string());
            }
        }

        return new FetchBodyDataSpecifier.response(section_part, part_number, subset_start,
            field_names);
    }

    /**
     * Omit the space between "header.fields" and the list of email headers.
     *
     * Some servers in the wild don't recognize the FETCH command if this space is present, and
     * so this allows for it to be omitted when serializing the request.  This appears to be in
     * violation of the IMAP specification, but these servers still exist.
     *
     * This should be used with care.  If enabled, a lot of servers will not accept the FETCH
     * command for the same reason (unrecognized request).
     *
     * Once set, this cannot be cleared.  To do so, create a new {@link FetchBodyDataSpecifier}.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-6.4.5]]
     * and [[https://bugzilla.gnome.org/show_bug.cgi?id=714902]]
     */
    public void omit_request_header_fields_space() {
        request_header_fields_space = false;
    }

    /**
     * {@link FetchBodyDataSpecifier}s are considered equal if they're serialized responses are
     * equal.
     *
     * This is because it's perceived that a corresponding request and response specifier may be
     * compared, but because of syntactic differences, are not strictly textually equal.  By
     * comparing how each specifier appears in its response format (which is a subset of the
     * parameters available in a request), a comparison is available.
     */
    public bool equal_to(FetchBodyDataSpecifier other) {
        if (this == other)
            return true;

        return hashable == other.hashable;
    }

    public uint hash() {
        return str_hash(hashable);
    }

    // Return serialize_request() because it's a more fuller representation than what the server returns
    public string to_string() {
        return serialize_request();
    }
}

