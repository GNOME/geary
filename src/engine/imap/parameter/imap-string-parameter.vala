/* Copyright 2016 Software Freedom Conservancy Inc.
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
     * The unquoted, decoded string as 7-bit ASCII.
     */
    public string ascii { get; private set; }

    /**
     * Returns {@link ascii} or null if value is empty (zero-length).
     */
    public string? nullable_ascii {
        get {
            return String.is_empty(ascii) ? null : ascii;
        }
    }

    protected StringParameter(string ascii) {
        this.ascii = ascii;
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
     * @throws ImapError.NOT_SUPPORTED if the string must be represented as a {@link LiteralParameter}.
     * @see Parameter.get_for_string
     */
    public static StringParameter get_best_for(string value) throws ImapError {
        if (NumberParameter.is_ascii_numeric(value, null))
            return new NumberParameter.from_ascii(value);

        switch (DataFormat.is_quoting_required(value)) {
            case DataFormat.Quoting.REQUIRED:
                return new QuotedStringParameter(value);

            case DataFormat.Quoting.OPTIONAL:
                return new UnquotedStringParameter(value);

            case DataFormat.Quoting.UNALLOWED:
                throw new ImapError.NOT_SUPPORTED("String must be a literal parameter");

            default:
                assert_not_reached();
        }
    }

    /**
     * Like {@link get_best_for} but the library will panic if the value cannot be turned into
     * a {@link StringParameter}.
     *
     * This should ''only'' be used with string constants that are guaranteed 7-bit ASCII.
     */
    public static StringParameter get_best_for_unchecked(string value) {
        try {
            return get_best_for(value);
        } catch (ImapError ierr) {
            error("Unable to create StringParameter for \"%s\": %s", value, ierr.message);
        }
    }

    /**
     * Like {@link get_best_for} but returns null if the value cannot be stored as a
     * {@link StringParameter}.
     *
     * @see Parameter.get_for_string
     */
    public static StringParameter? try_get_best_for(string value) {
        try {
            return get_best_for(value);
        } catch (ImapError ierr) {
            return null;
        }
    }

    /**
     * Can be used by subclasses to properly serialize the string value according to quoting rules.
     *
     * NOTE: Literal data is not currently supported.
     */
    protected void serialize_string(Serializer ser,
                                    GLib.Cancellable cancellable)
        throws GLib.Error {
        switch (DataFormat.is_quoting_required(ascii)) {
            case DataFormat.Quoting.REQUIRED:
                ser.push_quoted_string(ascii, cancellable);
            break;

            case DataFormat.Quoting.OPTIONAL:
                ser.push_unquoted_string(ascii, cancellable);
            break;

            case DataFormat.Quoting.UNALLOWED:
                error("Unable to serialize literal data");

            default:
                assert_not_reached();
        }
    }

    /**
     * Returns the string as a {@link Memory.Buffer}.
     */
    public Memory.Buffer as_buffer() {
        return new Memory.StringBuffer(ascii);
    }

    /**
     * Returns true if the string is empty (zero-length).
     */
    public bool is_empty() {
        return String.is_empty(ascii);
    }

    /**
     * Case-sensitive comparison.
     */
    public bool equals_cs(string value) {
        return Ascii.str_equal(ascii, value);
    }

    /**
     * Case-insensitive comparison.
     */
    public bool equals_ci(string value) {
        return Ascii.stri_equal(ascii, value);
    }

    /**
     * Returns the string in lowercase.
     */
    public string as_lower() {
        return Ascii.strdown(ascii);
    }

    /**
     * Returns the string uppercased.
     */
    public string as_upper() {
        return Ascii.strup(ascii);
    }

    /**
     * Converts the {@link ascii} to a signed 32-bit integer, clamped between clamp_min and
     * clamp_max.
     *
     * @throws ImapError.INVALID if the {@link StringParameter} contains non-numeric values.  No
     * error is thrown if the numeric value is outside the clamped range.
     */
    public int32 as_int32(int32 clamp_min = int32.MIN, int32 clamp_max = int32.MAX) throws ImapError {
        if (!NumberParameter.is_ascii_numeric(ascii, null))
            throw new ImapError.INVALID("Cannot convert \"%s\" to int32: not numeric", ascii);

        return (int32) int64.parse(ascii).clamp(clamp_min, clamp_max);
    }

    /**
     * Converts the {@link ascii} to a signed 64-bit integer, clamped between clamp_min and
     * clamp_max.
     *
     * @throws ImapError.INVALID if the {@link StringParameter} contains non-numeric values.  No
     * error is thrown if the numeric value is outside the clamped range.
     */
    public int64 as_int64(int64 clamp_min = int64.MIN, int64 clamp_max = int64.MAX) throws ImapError {
        if (!NumberParameter.is_ascii_numeric(ascii, null))
            throw new ImapError.INVALID("Cannot convert \"%s\" to int64: not numeric", ascii);

        return int64.parse(ascii).clamp(clamp_min, clamp_max);
    }

    /**
     * Attempts to coerce a {@link StringParameter} into a {@link NumberParameter}.
     *
     * Returns null if unsuitable for a NumberParameter.
     *
     * @see NumberParameter.is_ascii_numeric
     */
    public NumberParameter? coerce_to_number_parameter() {
        NumberParameter? numberp = this as NumberParameter;
        if (numberp != null)
            return numberp;

        if (NumberParameter.is_ascii_numeric(ascii, null))
            return new NumberParameter.from_ascii(ascii);

        return null;
    }
}

