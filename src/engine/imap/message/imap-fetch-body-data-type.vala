/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A symbolic representation of IMAP FETCH's BODY section parameter.
 *
 * This is only used with {@link FetchCommand}.  Most IMAP FETCH calls can be achieved with
 * plain {@link FetchDataType} specifiers.  Some cannot, however, and this more complicated
 * specifier must be used.
 *
 * A fully-qualified specifier looks something like this:
 *
 * BODY[part_number.section_part]<subset_start.subset_count>
 *
 * or, when headers are specified:
 *
 * BODY[part_number.section_part (header_fields)]<subset_start.subset_count>
 *
 * Note that Gmail apparently doesn't like BODY[1.TEXT] and instead must be specified with
 * BODY[1].  Also note that there's a PEEK variant that will not add the /Seen flag to the message.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6.4.5]], specifically section on
 * BODY[<section>]<<partial>>.
 *
 * @see FetchDataType
 */

public class Geary.Imap.FetchBodyDataType : BaseObject {
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
        
        public string to_string() {
            return serialize();
        }
    }
    
    private SectionPart section_part;
    private int[]? part_number;
    private int partial_start;
    private int partial_count;
    private string[]? field_names;
    private bool is_peek;
    
    /**
     * Create a FetchBodyDataType with the various required and optional parameters specified.
     *
     * Set part_number to null to ignore.  Set partial_start less than zero to ignore.
     * partial_count must be greater than zero if partial_start is greater than zero.
     *
     * field_names are required for {@link SectionPart.HEADER_FIELDS} and
     * {@link SectionPart.HEADER_FIELDS_NOT} and must be null for all other {@link SectionPart}s.
     */
    public FetchBodyDataType(SectionPart section_part, int[]? part_number, int partial_start,
        int partial_count, string[]? field_names) {
        init(section_part, part_number, partial_start, partial_count, field_names, false);
    }
    
    /**
     * Like FetchBodyDataType, but the /Seen flag will not be set when used on a message.
     */
    public FetchBodyDataType.peek(SectionPart section_part, int[]? part_number, int partial_start,
        int partial_count, string[]? field_names) {
        init(section_part, part_number, partial_start, partial_count, field_names, true);
    }
    
    private void init(SectionPart section_part, int[]? part_number, int partial_start, int partial_count,
        string[]? field_names, bool is_peek) {
        switch (section_part) {
            case SectionPart.HEADER_FIELDS:
            case SectionPart.HEADER_FIELDS_NOT:
                assert(field_names != null && field_names.length > 0);
            break;
            
            default:
                assert(field_names == null);
            break;
        }
        
        if (partial_start >= 0)
            assert(partial_count > 0);
        
        this.section_part = section_part;
        this.part_number = part_number;
        this.partial_start = partial_start;
        this.partial_count = partial_count;
        this.field_names = field_names;
        this.is_peek = is_peek;
    }
    
    /**
     * Returns the {@link FetchBodyDataType} in a string ready for a {@link Command}.
     */
    public string serialize_request() {
        return (!is_peek ? "body[%s%s%s]%s" : "body.peek[%s%s%s]%s").printf(
            serialize_part_number(),
            section_part.serialize(),
            serialize_field_names(),
            serialize_partial(true));
    }
    
    /**
     * Returns the {@link FetchBodyDataType} in a string as it might appear in a
     * {@link ServerResponse}.
     *
     * The FetchBodyDataType server response does not include the peek modifier or the span
     * length if a span was indicated (as the following literal specifies its length).
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-7.4.2]]
     */
    internal string serialize_response() {
        return "body[%s%s%s]%s".printf(
            serialize_part_number(),
            section_part.serialize(),
            serialize_field_names(),
            serialize_partial(false));
    }
    
    public Parameter to_request_parameter() {
        // Because of the kooky formatting of the Body[section]<partial> fetch field, use an
        // unquoted string and format it ourselves.
        return new UnquotedStringParameter(serialize_request());
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
        if (field_names == null || field_names.length == 0)
            return "";
        
        // note that the leading space is supplied here
        StringBuilder builder = new StringBuilder(" (");
        for (int ctr = 0; ctr < field_names.length; ctr++) {
            builder.append(field_names[ctr]);
            if (ctr < (field_names.length - 1))
                builder.append_c(' ');
        }
        builder.append_c(')');
        
        return builder.str;
    }
    
    // See note at serialize_response for reason is_request is necessary.
    private string serialize_partial(bool is_request) {
        if (is_request)
            return (partial_start < 0) ? "" : "<%d.%d>".printf(partial_start, partial_count);
        else
            return (partial_start < 0) ? "" : "<%d>".printf(partial_start);
    }
    
    /**
     * Returns true if the {@link StringParameter} is formatted like a {@link FetchBodyDataType}.
     *
     * Currently this test isn't perfect and should only be used as a guide.  There is no
     * decode or deserialize method for FetchBodyDataType.
     *
     * @see get_identifier
     */
    public static bool is_fetch_body(StringParameter items) {
        string strd = items.value.down();
        
        return strd.has_prefix("body[") || strd.has_prefix("body.peek[");
    }
    
    /**
     * Returns a {@link FetchBodyDataIdentifier} than can be used to compare results from
     * server responses with requested specifiers.
     *
     * Because no decode or deserialize method currently exists for {@link FetchBodyDataType},
     * the easiest way to determine if a response contains requested data is to compare it with
     * this returned object.
     */
    public FetchBodyDataIdentifier get_identifer() {
        return new FetchBodyDataIdentifier(this);
    }
    
    // Return serialize() because it's a more fuller representation than what the server returns
    public string to_string() {
        return serialize_request();
    }
}

