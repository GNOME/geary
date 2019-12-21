/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the RFC 2183 Content-Disposition field.
 *
 * See [[https://tools.ietf.org/html/rfc2183]]
 */

public class Geary.Mime.ContentDisposition : Geary.BaseObject {
    /**
     * Filename parameter name.
     *
     * See [[https://tools.ietf.org/html/rfc2183#section-2.3]]
     */
    public const string FILENAME = "filename";

    /**
     * Creation-Date parameter name.
     *
     * See [[https://tools.ietf.org/html/rfc2183#section-2.4]]
     */
    public const string CREATION_DATE = "creation-date";

    /**
     * Modification-Date parameter name.
     *
     * See [[https://tools.ietf.org/html/rfc2183#section-2.5]]
     */
    public const string MODIFICATION_DATE = "modification-date";

    /**
     * Read-Date parameter name.
     *
     * See [[https://tools.ietf.org/html/rfc2183#section-2.6]]
     */
    public const string READ_DATE = "read-date";

    /**
     * Size parameter name.
     *
     * See [[https://tools.ietf.org/html/rfc2183#section-2.7]]
     */
    public const string SIZE = "size";

    /**
     * The {@link DispositionType}, which is {@link DispositionType.UNSPECIFIED} if not specified.
     */
    public DispositionType disposition_type { get; private set; }

    /**
     * True if the original DispositionType was unknown.
     */
    public bool is_unknown_disposition_type { get; private set; }

    /**
     * The original disposition type string.
     */
    public string? original_disposition_type_string { get; private set; }

    /**
     * Various parameters associated with the content's disposition.
     *
     * This is never null.  Rather, an empty ContentParameters is held if the Content-Type has
     * no parameters.
     *
     * @see FILENAME
     * @see CREATION_DATE
     * @see MODIFICATION_DATE
     * @see READ_DATE
     * @see SIZE
     */
    public ContentParameters params { get; private set; }

    /**
     * Create a Content-Disposition representation
     */
    public ContentDisposition(string? disposition, ContentParameters? params) {
        bool is_unknown;
        disposition_type = DispositionType.deserialize(disposition, out is_unknown);
        is_unknown_disposition_type = is_unknown;
        original_disposition_type_string = disposition;
        this.params = params ?? new ContentParameters();
    }

    /**
     * Create a simplified Content-Disposition representation.
     */
    public ContentDisposition.simple(DispositionType disposition_type) {
        this.disposition_type = disposition_type;
        is_unknown_disposition_type = false;
        original_disposition_type_string = null;
        this.params = new ContentParameters();
    }

    internal ContentDisposition.from_gmime(GMime.ContentDisposition content_disposition) {
        bool is_unknown;
        disposition_type = DispositionType.deserialize(content_disposition.get_disposition(),
            out is_unknown);
        is_unknown_disposition_type = is_unknown;
        original_disposition_type_string = content_disposition.get_disposition();
        params = new ContentParameters.from_gmime(content_disposition.get_parameters());
    }
}

