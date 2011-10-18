/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.FetchBodyDataType {
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
    private string[]? field_names;
    private bool is_peek;
    
    /**
     * field_names are required for SectionPart.HEADER_FIELDS and SectionPart.HEADER_FIELDS_NOT
     * and must be null for all other SectionParts.
     */
    public FetchBodyDataType(SectionPart section_part, string[]? field_names) {
        init(section_part, field_names, false);
    }
    
    /**
     * Like FetchBodyDataType, but the /seen flag will not be set when used on a message.
     */
    public FetchBodyDataType.peek(SectionPart section_part, string[]? field_names) {
        init(section_part, field_names, true);
    }
    
    private void init(SectionPart section_part, string[]? field_names, bool is_peek) {
        switch (section_part) {
            case SectionPart.HEADER_FIELDS:
            case SectionPart.HEADER_FIELDS_NOT:
                assert(field_names != null && field_names.length > 0);
            break;
            
            default:
                assert(field_names == null);
            break;
        }
        
        this.section_part = section_part;
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
    
    public static bool is_fetch_body(StringParameter items) {
        string strd = items.value.down();
        
        return strd.has_prefix("body[") || strd.has_prefix("body.peek[");
    }
    
    public string to_string() {
        return (!is_peek ? "body[%s%s]" : "body.peek[%s%s]").printf(section_part.serialize(),
            serialize_field_names());
    }
}

