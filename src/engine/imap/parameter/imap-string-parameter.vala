/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A base abstract representation of string (text) data in IMAP.
 *
 * Although they may be transmitted in various ways, most parameters in IMAP are strings or text
 * format, possibly with some quoting rules applied.  This class handles most issues with these
 * types of {@link Parameter}s.
 *
 * Although the IMAP specification doesn't list an atom as a "string", it is here because of the
 * common functionality that is needed for comparison and other operations.
 *
 * Note that {@link NilParameter} is ''not'' a StringParameter, to avoid type confusion.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.3]]
 */

public abstract class Geary.Imap.StringParameter : Geary.Imap.Parameter {
    /**
     * The unquoted, decoded string.
     */
    public string value { get; private set; }
    
    /**
     * Returns {@link value} or null if value is empty (zero-length).
     */
    public string? nullable_value {
        get {
            return String.is_empty(value) ? null : value;
        }
    }
    
    protected StringParameter(string value) {
        this.value = value;
    }
    
    /**
     * Returns a {@link StringParameter} appropriate for the contents of value.
     *
     * Will not return an {@link AtomParameter}, but rather an {@link UnquotedStringParameter} if
     * suitable.  Will not return a {@link NilParameter} for empty strings, but rather a
     * {@link QuotedStringParameter}.
     *
     * Because of these restrictions, should only be used when the context or syntax of the
     * Parameter is unknown or uncertain.
     *
     * @return null if the string must be represented with a {@link LiteralParameter}.
     */
    public static StringParameter? get_best_for(string value) {
        if (NumberParameter.is_numeric(value, null))
            return new NumberParameter.from_string(value);
        
        switch (DataFormat.is_quoting_required(value)) {
            case DataFormat.Quoting.REQUIRED:
                return new QuotedStringParameter(value);
            
            case DataFormat.Quoting.OPTIONAL:
                return new UnquotedStringParameter(value);
            
            case DataFormat.Quoting.UNALLOWED:
                return null;
            
            default:
                assert_not_reached();
        }
    }
    
    /**
     * Can be used by subclasses to properly serialize the string value according to quoting rules.
     *
     * NOTE: Literal data is not currently supported.
     */
    protected void serialize_string(Serializer ser) throws Error {
        switch (DataFormat.is_quoting_required(value)) {
            case DataFormat.Quoting.REQUIRED:
                ser.push_quoted_string(value);
            break;
            
            case DataFormat.Quoting.OPTIONAL:
                ser.push_unquoted_string(value);
            break;
            
            case DataFormat.Quoting.UNALLOWED:
                error("Unable to serialize literal data");
            
            default:
                assert_not_reached();
        }
    }
    
    /**
     * Case-sensitive comparison.
     */
    public bool equals_cs(string value) {
        return Ascii.str_equal(this.value, value);
    }
    
    /**
     * Case-insensitive comparison.
     */
    public bool equals_ci(string value) {
        return Ascii.stri_equal(this.value, value);
    }
    
    /**
     * Returns the string lowercased.
     */
    public string as_lower() {
        return Ascii.strdown(value);
    }
    
    /**
     * Returns the string uppercased.
     */
    public string as_upper() {
        return Ascii.strup(value);
    }
    
    /**
     * Converts the {@link value} to an int, clamped between clamp_min and clamp_max.
     *
     * TODO: This does not check that the value is a properly-formed integer.  This should be
     *. added later.
     */
    public int as_int(int clamp_min = int.MIN, int clamp_max = int.MAX) throws ImapError {
        return int.parse(value).clamp(clamp_min, clamp_max);
    }
    
    /**
     * Converts the {@link value} to a long integer, clamped between clamp_min and clamp_max.
     *
     * TODO: This does not check that the value is a properly-formed long integer.  This should be
     *. added later.
     */
    public long as_long(int clamp_min = int.MIN, int clamp_max = int.MAX) throws ImapError {
        return long.parse(value).clamp(clamp_min, clamp_max);
    }
    
    /**
     * Converts the {@link value} to a 64-bit integer, clamped between clamp_min and clamp_max.
     *
     * TODO: This does not check that the value is a properly-formed 64-bit integer.  This should be
     *. added later.
     */
    public int64 as_int64(int64 clamp_min = int64.MIN, int64 clamp_max = int64.MAX) throws ImapError {
        return int64.parse(value).clamp(clamp_min, clamp_max);
    }
}

