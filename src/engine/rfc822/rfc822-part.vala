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


    /** Specifies a character set encoding when writing text bodies. */
    public enum EncodingConversion {

        /** No conversion will be applied. */
        NONE,

        /** Plain text bodies will be converted to UTF-8. */
        UTF8;
    }

    /** Specifies a format to apply when writing text bodies. */
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

    public Memory.Buffer write_to_buffer(EncodingConversion conversion,
                                         BodyFormatting format = BodyFormatting.NONE)
        throws Error {
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);

        write_to_stream(stream, conversion, format);

        return new Geary.Memory.ByteBuffer.from_byte_array(byte_array);
    }

    internal void write_to_stream(GMime.Stream destination,
                                  EncodingConversion conversion,
                                  BodyFormatting format = BodyFormatting.NONE)
        throws Error {
        GMime.DataWrapper? wrapper = (this.source_part != null)
            ? this.source_part.get_content() : null;
        if (wrapper == null) {
            throw new Error.INVALID(
                "Could not get the content wrapper for content-type %s",
                content_type.to_string()
            );
        }

        if (this.content_type.is_type("text", Mime.ContentType.WILDCARD)) {
            GMime.StreamFilter filter = new GMime.StreamFilter(destination);

            // Do charset conversion if needed
            string? charset = this.content_type.params.get_value("charset");
            if (String.is_empty(charset)) {
                // Fallback charset per RFC 2045, Section 5.2
                charset = "US-ASCII";
            }
            if (conversion == UTF8 && !is_utf_8(charset)) {
                GMime.FilterCharset? filter_charset = new GMime.FilterCharset(
                    charset, Geary.RFC822.UTF8_CHARSET
                );
                if (filter_charset == null) {
                    // Source charset not supported, so assume
                    // US-ASCII
                    filter_charset = new GMime.FilterCharset(
                        "US-ASCII", Geary.RFC822.UTF8_CHARSET
                    );
                }
                filter.add(filter_charset);
            }

            bool flowed = content_type.params.has_value_ci("format", "flowed");
            bool delsp = content_type.params.has_value_ci("DelSp", "yes");

            // Remove the CR's in any CRLF sequence since they are
            // effectively a wire encoding, unless the format requires
            // them or the content encoding is Base64 (being a binary
            // format)
            if ((this.source_part == null ||
                 this.source_part.encoding != BASE64) &&
                !(content_type.media_subtype in CR_PRESERVING_TEXT_TYPES)) {
                filter.add(new GMime.FilterDos2Unix(false));
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

            if (wrapper.write_to_stream(filter) < 0)
                throw new Error.FAILED("Unable to write textual RFC822 part to filter stream");
            if (filter.flush() != 0)
                throw new Error.FAILED("Unable to flush textual RFC822 part to destination stream");
            if (destination.flush() != 0)
                throw new Error.FAILED("Unable to flush textual RFC822 part to destination");
        } else {
            // Keep as binary
            if (wrapper.write_to_stream(destination) < 0)
                throw new Error.FAILED("Unable to write binary RFC822 part to destination stream");
            if (destination.flush() != 0)
                throw new Error.FAILED("Unable to flush binary RFC822 part to destination");
        }
    }

}
