/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an RFC 2045 MIME Content-Type field.
 *
 * See [[https://tools.ietf.org/html/rfc2045#section-5]]
 */

public class Geary.Mime.ContentType : Geary.BaseObject {
    /*
     * MIME wildcard for comparing {@link media_type} and {@link media_subtype}.
     *
     * @see is_type
     */
    public const string WILDCARD = "*";
    
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
        params = new ContentParameters.from_gmime(content_type.get_params());
    }
    
    public static ContentType deserialize(string str) throws MimeError {
        // perform a little sanity checking here, as it doesn't appear the GMime constructor has
        // any error-reporting at all
        if (String.is_empty(str))
            throw new MimeError.PARSE("Empty MIME Content-Type");
        
        if (!str.contains("/"))
            throw new MimeError.PARSE("Invalid MIME Content-Type: %s", str); 
        
        return new ContentType.from_gmime(new GMime.ContentType.from_string(str));
    }
    
    /**
     * Compares the {@link media_type} with the supplied type.
     *
     * An asterisk ("*") or {@link WILDCARD) are accepted, which will always return true.
     *
     * @see is_type
     */
    public bool has_media_type(string media_type) {
        return (media_type != WILDCARD) ? String.stri_equal(this.media_type, media_type) : true;
    }
    
    /**
     * Compares the {@link media_subtype} with the supplied subtype.
     *
     * An asterisk ("*") or {@link WILDCARD) are accepted, which will always return true.
     *
     * @see is_type
     */
    public bool has_media_subtype(string media_subtype) {
        return (media_subtype != WILDCARD) ? String.stri_equal(this.media_subtype, media_subtype) : true;
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

