/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an RFC 2045 MIME Content-Type field.
 *
 * See [[https://tools.ietf.org/html/rfc2045#section-5]]
 *
 * This class is immutable.
 */
public class Geary.Mime.ContentType : Geary.BaseObject {

    /**
     * MIME wildcard for comparing {@link media_type} and {@link media_subtype}.
     *
     * @see is_type
     */
    public const string WILDCARD = "*";

    /**
     * Default Content-Type for inline, displayed entities.
     *
     * This is as specified by RFC 2052 § 5.2.
     */
    public static ContentType DISPLAY_DEFAULT;

    /**
     * Default Content-Type for attached entities.
     *
     * Although RFC 2052 § 5.2 specifies US-ASCII as the default, for
     * attachments assume a binary blob so that users aren't presented
     * with garbled text editor content and warnings on opening it.
     */
    public static ContentType ATTACHMENT_DEFAULT;


    private static Gee.Map<string,string> TYPES_TO_EXTENSIONS =
        new Gee.HashMap<string,string>();

    static construct {
        DISPLAY_DEFAULT = new ContentType(
            "text", "plain",
            new ContentParameters.from_array({{"charset", "us-ascii"}})
        );
        ATTACHMENT_DEFAULT = new ContentType("application", "octet-stream", null);

        // XXX We should be loading file name extension information
        // from /etc/mime.types and/or the XDG Shared MIME-info
        // Database globs2 file, usually located at
        // "/usr/share/mime/globs2" (See: {@link
        // https://specifications.freedesktop.org/shared-mime-info-spec/latest/}).
        //
        // But for now the most part the only things that we have to
        // guess this for are inline embeds that don't have filenames,
        // i.e. images, so we can hopefully get away with the set
        // below for now.
        TYPES_TO_EXTENSIONS["image/jpeg"] = ".jpeg";
        TYPES_TO_EXTENSIONS["image/png"] = ".png";
        TYPES_TO_EXTENSIONS["image/gif"] = ".gif";
        TYPES_TO_EXTENSIONS["image/svg+xml"] = ".svg";
        TYPES_TO_EXTENSIONS["image/bmp"] = ".bmp";
        TYPES_TO_EXTENSIONS["image/x-bmp"] = ".bmp";
    }

    public static ContentType parse(string str) throws MimeError {
        // perform a little sanity checking here, as it doesn't appear
        // the GMime constructor has any error-reporting at all
        if (String.is_empty(str))
            throw new MimeError.PARSE("Empty MIME Content-Type");

        if (!str.contains("/"))
            throw new MimeError.PARSE("Invalid MIME Content-Type: %s", str);

        return new ContentType.from_gmime(GMime.ContentType.parse(
          Geary.RFC822.get_parser_options(),
          str
        ));
    }

    /**
     * Attempts to guess the content type for a buffer using GIO sniffing.
     *
     * Returns null if it could not be guessed.
     */
    public static ContentType? guess_type(string? file_name, Geary.Memory.Buffer? buf)
        throws Error {
        string? mime_type = null;

        if (file_name != null) {
            // XXX might just want to use xdgmime lib directly here to
            // avoid the intermediate glib_content_type step here?
            string glib_type = GLib.ContentType.guess(file_name, null, null);
            mime_type = GLib.ContentType.get_mime_type(glib_type);
            if (Geary.String.is_empty(mime_type)) {
                mime_type = null;
            }
        }

        if (mime_type == null && buf != null) {
            int max_len = 4096;
            // XXX determine actual max needed buffer size using
            // xdg_mime_get_max_buffer_extents?
            uint8[] data = (buf.size <= max_len)
                ? buf.get_uint8_array()
                : buf.get_bytes()[0:max_len].get_data();

            // XXX might just want to use xdgmime lib directly here to
            // avoid the intermediate glib_content_type step here?
            string glib_type = GLib.ContentType.guess(null, data, null);
            mime_type = GLib.ContentType.get_mime_type(glib_type);
        }

        return (
            !Geary.String.is_empty_or_whitespace(mime_type)
            ? ContentType.parse(mime_type)
            : null
        );
    }


    /**
     * The type (discrete or concrete) portion of the Content-Type field.
     *
     * It's highly recommended the caller use the various ''has'' and ''is'' methods when performing
     * comparisons rather than direct string operations.
     *
     * media_type may be {@link WILDCARD}, in which case it matches with any other media_type.
     *
     * @see has_media_type
     */
    public string media_type { get; private set; }

    /**
     * The subtype (extension-token or iana-token) portion of the Content-Type field.
     *
     * It's highly recommended the caller use the various ''has'' and ''is'' methods when performing
     * comparisons rather than direct string operations.
     *
     * media_subtype may be {@link WILDCARD}, in which case it matches with any other media_subtype.
     *
     * @see has_media_subtype
     */
    public string media_subtype { get; private set; }

    /**
     * Content parameters, if any, in the Content-Type field.
     *
     * This is never null.  Rather, an empty ContentParameters is held if the Content-Type has
     * no parameters.
     */
    public ContentParameters params { get; private set; }

    /**
     * Create a MIME Content-Type representative object.
     */
    public ContentType(string media_type, string media_subtype, ContentParameters? params) {
        this.media_type = media_type.strip();
        this.media_subtype = media_subtype.strip();
        this.params = params ?? new ContentParameters();
    }

    internal ContentType.from_gmime(GMime.ContentType content_type) {
        media_type = content_type.get_media_type().strip();
        media_subtype = content_type.get_media_subtype().strip();
        params = new ContentParameters.from_gmime(content_type.get_parameters());
    }

    /**
     * Compares the {@link media_type} with the supplied type.
     *
     * An asterisk ("*") or {@link WILDCARD} are accepted, which will always return true.
     *
     * @see is_type
     */
    public bool has_media_type(string media_type) {
        return (media_type != WILDCARD) ? Ascii.stri_equal(this.media_type, media_type) : true;
    }

    /**
     * Compares the {@link media_subtype} with the supplied subtype.
     *
     * An asterisk ("*") or {@link WILDCARD} are accepted, which will always return true.
     *
     * @see is_type
     */
    public bool has_media_subtype(string media_subtype) {
        return (media_subtype != WILDCARD) ? Ascii.stri_equal(this.media_subtype, media_subtype) : true;
    }

    /**
     * Returns the {@link ContentType}'s media content type (its "MIME type").
     *
     * This returns the bare MIME content type description lacking all parameters.  For example,
     * "image/jpeg; name='photo.JPG'" will be returned as "image/jpeg".
     *
     * @see serialize
     */
    public string get_mime_type() {
        return "%s/%s".printf(media_type, media_subtype);
    }

    /**
     * Returns the file name extension for this type, if known.
     */
    public string? get_file_name_extension() {
        return TYPES_TO_EXTENSIONS[get_mime_type()];
    }

    /**
     * Compares the supplied type and subtype with this instance's.
     *
     * Asterisks (or {@link WILDCARD}) may be supplied for either field.
     *
     * @see is_same
     */
    public bool is_type(string media_type, string media_subtype) {
        return has_media_type(media_type) && has_media_subtype(media_subtype);
    }

    /**
     * Compares this {@link ContentType} with another instance.
     *
     * This is slightly different than the notion of "equal to", as it's possible for
     * {@link ContentType} to hold {@link WILDCARD}s, which don't imply equality.
     *
     * @see is_type
     */
    public bool is_same(ContentType other) {
        return is_type(other.media_type, other.media_subtype);
    }

    /**
     * Compares the supplied MIME type (i.e. "image/jpeg") with this instance.
     *
     * As in {@link get_mime_type}, this method is only worried about the media type and subtype
     * in the supplied string.  Parameters are ignored.
     *
     * Throws {@link MimeError} if the supplied string doesn't look like a MIME type.
     */
    public bool is_mime_type(string mime_type) throws MimeError {
        int index = mime_type.index_of_char('/');
        if (index < 0)
            throw new MimeError.PARSE("Invalid MIME type: %s", mime_type);

        string mime_media_type = mime_type.substring(0, index).strip();

        string mime_media_subtype = mime_type.substring(index + 1);
        index = mime_media_subtype.index_of_char(';');
        if (index >= 0)
            mime_media_subtype = mime_media_subtype.substring(0, index);
        mime_media_subtype = mime_media_subtype.strip();

        if (String.is_empty(mime_media_type) || String.is_empty(mime_media_subtype))
            throw new MimeError.PARSE("Invalid MIME type: %s", mime_type);

        return is_type(mime_media_type, mime_media_subtype);
    }

    public string serialize() {
        StringBuilder builder = new StringBuilder();
        builder.append_printf("%s/%s", media_type, media_subtype);

        if (params != null && params.size > 0) {
            foreach (string attribute in params.attributes) {
                string value = params.get_value(attribute);

                switch (DataFormat.get_encoding_requirement(value)) {
                    case DataFormat.Encoding.QUOTING_OPTIONAL:
                        builder.append_printf("; %s=%s", attribute, value);
                    break;

                    case DataFormat.Encoding.QUOTING_REQUIRED:
                        builder.append_printf("; %s=\"%s\"", attribute, value);
                    break;

                    case DataFormat.Encoding.UNALLOWED:
                        message("Cannot encode ContentType param value %s=\"%s\": unallowed",
                            attribute, value);
                    break;

                    default:
                        assert_not_reached();
                }
            }
        }

        return builder.str;
    }

    public string to_string() {
        return serialize();
    }
}

