/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An RFC-2045 style MIME entity.
 *
 * This object provides a convenient means accessing the high-level
 * MIME entity header field values that are useful to applications and
 * decoded forms of the entity body.
 */
public class Geary.RFC822.Part : Object {


    /** Specifies a format to apply to body data when writing it. */
    public enum BodyFormatting {

        /** No formatting will be applied. */
        NONE,

        /** Plain text bodies will be formatted as HTML. */
        HTML;
    }


    // The set of text/* types that must have CRLF preserved, since it
    // is part of their format. These really should be under
    // application/*, but here we are.
    private static Gee.Set<string> CR_PRESERVING_TEXT_TYPES =
        new Gee.HashSet<string>();

    static construct {
        // VCard
        CR_PRESERVING_TEXT_TYPES.add("vcard");
        CR_PRESERVING_TEXT_TYPES.add("x-vcard");
        CR_PRESERVING_TEXT_TYPES.add("directory");

        // iCal
        CR_PRESERVING_TEXT_TYPES.add("calendar");

        // MS RTF
        CR_PRESERVING_TEXT_TYPES.add("rtf");
    }


    /**
     * The entity's Content-Type.
     *
     * See [[https://tools.ietf.org/html/rfc2045#section-5]]
     */
    public Mime.ContentType content_type { get; private set; }

    /**
     * The entity's Content-ID.
     *
     * See [[https://tools.ietf.org/html/rfc2045#section-5]],
     * [[https://tools.ietf.org/html/rfc2111]] and {@link
     * Email.get_attachment_by_content_id}.
     */
    public string? content_id { get; private set; }

    /**
     * The entity's Content-Description.
     *
     * See [[https://tools.ietf.org/html/rfc2045#section-8]]
     */
    public string? content_description { get; private set; }

    /**
     * The entity's Content-Disposition.
     *
     * See [[https://tools.ietf.org/html/rfc2183]]
     */
    public Mime.ContentDisposition? content_disposition { get; private set; }

    private GMime.Object source_object;
    private GMime.Part? source_part;


    internal Part(GMime.Object source) {
        this.source_object = source;
        this.source_part = source as GMime.Part;

        this.content_id = source.get_content_id();

        this.content_description = (this.source_part != null)
            ? source_part.get_content_description() : null;

        GMime.ContentDisposition? part_disposition =
            source.get_content_disposition();
        if (part_disposition != null) {
            this.content_disposition = new Mime.ContentDisposition.from_gmime(
                part_disposition
            );
        }

        // Although the GMime API permits this to be null, it's not
        // clear if it ever will be, since the API requires it to be
        // specified at construction time.
        GMime.ContentType? part_type = source.get_content_type();
        if (part_type != null) {
            this.content_type = new Mime.ContentType.from_gmime(part_type);
        } else {
            Mime.DispositionType disposition = Mime.DispositionType.UNSPECIFIED;
            if (this.content_disposition != null) {
                disposition = this.content_disposition.disposition_type;
            }
            this.content_type = (disposition != Mime.DispositionType.ATTACHMENT)
                ? Mime.ContentType.DISPLAY_DEFAULT
                : Mime.ContentType.ATTACHMENT_DEFAULT;
        }
    }

    /**
     * Returns the entity's filename, cleaned for use in the file system.
     */
    public string? get_clean_filename() {
        string? filename = (this.source_part != null)
            ? this.source_part.get_filename() : null;
        if (filename != null) {
            try {
                filename = invalid_filename_character_re.replace_literal(
                    filename, filename.length, 0, "_"
                );
            } catch (RegexError e) {
                debug("Error sanitizing attachment filename: %s", e.message);
            }
        }
        return filename;
    }

    public Memory.Buffer write_to_buffer(BodyFormatting format = BodyFormatting.NONE)
        throws RFC822Error {
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);

        write_to_stream(stream, format);

        return new Geary.Memory.ByteBuffer.from_byte_array(byte_array);
    }

    internal void write_to_stream(GMime.Stream destination,
                                  BodyFormatting format = BodyFormatting.NONE)
        throws RFC822Error {
        GMime.DataWrapper? wrapper = (this.source_part != null)
            ? this.source_part.get_content_object() : null;
        if (wrapper == null) {
            throw new RFC822Error.INVALID(
                "Could not get the content wrapper for content-type %s",
                content_type.to_string()
            );
        }

        Mime.ContentType content_type = this.get_effective_content_type();
        if (content_type.is_type("text", Mime.ContentType.WILDCARD)) {
            // Assume encoded text, convert to unencoded UTF-8
            GMime.StreamFilter filter = new GMime.StreamFilter(destination);
            string? charset = content_type.params.get_value("charset");
            filter.add(
                Geary.RFC822.Utils.create_utf8_filter_charset(charset)
            );

            bool flowed = content_type.params.has_value_ci("format", "flowed");
            bool delsp = content_type.params.has_value_ci("DelSp", "yes");

            // Remove the CR's in any CRLF sequence since they are
            // effectively a wire encoding, unless the format requires
            // them.
            if (!(content_type.media_subtype in CR_PRESERVING_TEXT_TYPES)) {
                filter.add(new GMime.FilterCRLF(false, false));
            }

            if (flowed) {
                filter.add(
                    new Geary.RFC822.FilterFlowed(
                        format == BodyFormatting.HTML, delsp
                    )
                );
            }

            if (format == BodyFormatting.HTML) {
                if (!flowed) {
                    filter.add(new Geary.RFC822.FilterPlain());
                }
                filter.add(
                    new GMime.FilterHTML(
                        GMime.FILTER_HTML_CONVERT_URLS |
                        GMime.FILTER_HTML_CONVERT_ADDRESSES,
                        0
                    )
                );
                filter.add(new Geary.RFC822.FilterBlockquotes());
            }

            wrapper.write_to_stream(filter);
            filter.flush();
        } else {
            // Keep as binary
            wrapper.write_to_stream(destination);
            destination.flush();
        }
    }

}
