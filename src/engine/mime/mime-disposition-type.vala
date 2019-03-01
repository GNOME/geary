/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of a MIME Content-Disposition type field.
 *
 * Note that NONE only indicates that the Content-Disposition type field was not present.
 * RFC 2183 Section 2.8 specifies that unknown type fields should be treated as attachments,
 * which is true in this code as well.
 *
 * These values may be persisted on disk and should not be modified unless you know what
 * you're doing.  (Legacy code requires that NONE be -1.)
 *
 * See [[https://tools.ietf.org/html/rfc2183#section-2]]
 */

public enum Geary.Mime.DispositionType {
    UNSPECIFIED = -1,
    ATTACHMENT = 0,
    INLINE = 1;

    /**
     * Convert the disposition-type field into an internal representation.
     *
     * Empty or blank fields result in {@link UNSPECIFIED}.  Unknown fields are converted to
     * {@link ATTACHMENT} as per RFC 2183 Section 2.8.  However, since the caller may want to
     * make a decision about unknown vs. unspecified type fields, is_unknown is returned as well.
     */
    public static DispositionType deserialize(string? str, out bool is_unknown) {
        is_unknown = false;

        if (String.is_empty_or_whitespace(str))
            return UNSPECIFIED;

        switch (Ascii.strdown(str)) {
            case "inline":
                return INLINE;

            case "attachment":
                return ATTACHMENT;

            default:
                is_unknown = true;

                return ATTACHMENT;
        }
    }

    /**
     * Returns null if value is {@link UNSPECIFIED}
     */
    public string? serialize() {
        switch (this) {
            case UNSPECIFIED:
                return null;

            case ATTACHMENT:
                return "attachment";

            case INLINE:
                return "inline";

            default:
                assert_not_reached();
        }
    }

    internal static DispositionType from_int(int i) {
        switch (i) {
            case INLINE:
                return INLINE;

            case UNSPECIFIED:
                return UNSPECIFIED;

            // see note in class description for why unknown content-dispositions are treated as
            // attachments
            case ATTACHMENT:
            default:
                return ATTACHMENT;
        }
    }
}

