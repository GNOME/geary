/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of a MIME multipart Content-Type subtype.
 *
 * See [[https://tools.ietf.org/html/rfc2046#section-5.1]]
 */

public enum Geary.Mime.MultipartSubtype {
    /**
     * Used as a placeholder for no or unknown multipart subtype.
     *
     * Technically an unknown or unspecified subtype should be treated as {@link MIXED}, but there
     * are situations in code where this is useful.
     */
    UNSPECIFIED,
    /**
     * A multipart structure of mixed media.
     *
     * "Any 'multipart' subtypes that an implementation does not recognize must be treated as
     * being of subtype 'mixed'."
     *
     * See [[https://tools.ietf.org/html/rfc2046#section-5.1.3]]
     */
    MIXED,
     /**
      * A multipart structure of alternative media.
      *
      * See [[https://tools.ietf.org/html/rfc2046#section-5.1.4]]
      */
    ALTERNATIVE,
     /**
      * A multipart structure of related media.
      *
      * See [[http://tools.ietf.org/html/rfc2387]]
      */
    RELATED;

    /**
     * Converts a {@link ContentType} into a {@link MultipartSubtype}.
     *
     * If unknown, {@link MIXED} is returned but is_unknown will be true.
     */
    public static MultipartSubtype from_content_type(ContentType? content_type, out bool is_unknown) {
        if (content_type == null || !content_type.has_media_type("multipart")) {
            is_unknown = true;

            return MIXED;
        }

        is_unknown = false;
        switch (Ascii.strdown(content_type.media_subtype)) {
            case "mixed":
                return MIXED;

            case "alternative":
                return ALTERNATIVE;

            case "related":
                return RELATED;

            default:
                is_unknown = true;

                return MIXED;
        }
    }
}

