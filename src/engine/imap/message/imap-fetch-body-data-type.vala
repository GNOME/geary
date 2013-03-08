/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.FetchBodyDataType : BaseObject {
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
     * See RFC-3501 6.4.5 for some light beach reading on how the FETCH body data specifier is formed.
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
     * BODY[1].
     *
     * Set part_number to null to ignore.  Set partial_start less than zero to ignore.
     * partial_count must be greater than zero if partial_start is greater than zero.
     *
     * field_names are required for SectionPart.HEADER_FIELDS and SectionPart.HEADER_FIELDS_NOT
     * and must be null for all other SectionParts.
     */
    public FetchBodyDataType(SectionPart section_part, int[]? part_number, int partial_start,
        int partial_count, string[]? field_names) {
        init(section_part, part_number, partial_start, partial_count, field_names, false);
    }
    
    /**
     * Like FetchBodyDataType, but the /seen flag will not be set when used on a message.
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
    
    public string serialize() {
        return to_string();
    }
    
    public Parameter to_parameter() {
        // Because of the kooky formatting of the Body[section]<partial> fetch field, use an
        // unquoted string and format it ourselves.
        return new UnquotedStringParameter(serialize());
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
    
    private string serialize_partial() {
        return (partial_start < 0) ? "" : "<%d.%d>".printf(partial_start, partial_count);
    }
    
    public static bool is_fetch_body(StringParameter items) {
        string strd = items.value.down();
        
        return strd.has_prefix("body[") || strd.has_prefix("body.peek[");
    }
    
    public string to_string() {
        return (!is_peek ? "body[%s%s%s]%s" : "body.peek[%s%s%s]%s").printf(
            serialize_part_number(),
            section_part.serialize(),
            serialize_field_names(),
            serialize_partial());
    }
}

