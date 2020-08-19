/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An optional response code accompanying a {@link ServerResponse}.
 *
 * See
 * [[http://tools.ietf.org/html/rfc3501#section-7.1]],
 * [[http://tools.ietf.org/html/rfc5530]], and
 * [[http://tools.ietf.org/html/rfc4315]]
 * for more information.
 */

public class Geary.Imap.ResponseCodeType : BaseObject, Gee.Hashable<ResponseCodeType> {
    public const string ALERT = "alert";
    public const string ALREADYEXISTS = "alreadyexists";
    public const string APPENDUID = "appenduid";
    public const string AUTHENTICATIONFAILED = "authenticationfailed";
    public const string AUTHORIZATIONFAILED = "authorizationfailed";
    public const string BADCHARSET = "badcharset";
    public const string CAPABILITY = "capability";
    public const string CLIENTBUG = "clientbug";
    public const string COPYUID = "copyuid";
    public const string MYRIGHTS = "myrights";
    public const string NEWNAME = "newname";
    public const string NONEXISTENT = "nonexistent";
    public const string PARSE = "parse";
    public const string PERMANENT_FLAGS = "permanentflags";
    public const string READONLY = "read-only";
    public const string READWRITE = "read-write";
    public const string SERVERBUG = "serverbug";
    public const string TRY_CREATE = "trycreate";
    public const string UIDVALIDITY = "uidvalidity";
    public const string UIDNEXT = "uidnext";
    public const string UNAVAILABLE = "unavailable";
    public const string UNSEEN = "unseen";

    /**
     * The original response code value submitted to the object (possibly off-the-wire).
     */
    public string original { get; private set; }

    /**
     * The response code value set to lowercase, making it easy to compare to constant strings
     * in a uniform way.
     */
    public string value { get; private set; }

    /**
     * Throws an {@link ImapError.INVALID} if the string cannot be represented as an
     * {link ResponseCodeType}.
     */
    public ResponseCodeType(string value) throws ImapError {
        init(value);
    }

    /**
     * Throws an {@link ImapError.INVALID} if the {@link StringParameter} cannot be represented as
     * an {link ResponseCodeType}.
     */
    public ResponseCodeType.from_parameter(StringParameter stringp) throws ImapError {
        init(stringp.ascii);
    }

    private void init(string ascii) throws ImapError {
        // note that is_quoting_required() also catches empty strings (as they require quoting)
        if (DataFormat.is_quoting_required(ascii) != DataFormat.Quoting.OPTIONAL)
            throw new ImapError.INVALID("\"%s\" cannot be represented as a ResponseCodeType", ascii);

        // store in lowercase so it's easily compared with const strings above
        original = ascii;
        value = Ascii.strdown(ascii);
    }

    public bool is_value(string str) {
        return Ascii.stri_equal(value, str);
    }

    public StringParameter to_parameter() {
        return new AtomParameter(original);
    }

    public bool equal_to(ResponseCodeType other) {
        return (this == other) ? true : Ascii.stri_equal(value, other.value);
    }

    public uint hash() {
        return Ascii.stri_hash(value);
    }

    public string to_string() {
        return value;
    }
}

