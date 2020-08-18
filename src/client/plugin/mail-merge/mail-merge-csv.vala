/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


/** Denotes CSV-specific error conditions. */
public errordomain MailMerge.Csv.DataError {

    /** The input stream contained non-text data. */
    NON_TEXT_DATA,

    /** The end of line terminator could not be determined. */
    UNKNOWN_EOL,

    /** The end of line terminator was not found. */
    EOL_NOT_FOUND;
}


/**
 * A simple comma-separated value (CSV) reader.
 *
 * To use this class, simply construct an instance start calling
 * {@link read_record}.
 */
public class MailMerge.Csv.Reader : Geary.BaseObject {


    // UTF byte prefixes indicating multi-byte codepoints
    private const uint8 UTF8_DOUBLE = 0x06;    // `110`
    private const uint8 UTF8_TRIPLE = 0x0E;    // `1110`
    private const uint8 UTF8_QUADRUPLE = 0x1E; // `11110`
    private const uint8 UTF8_TRAILER = 0x02;   // `10`
    private const unichar UNICODE_REPLACEMENT_CHAR = 0xFFFD;


    private static inline bool is_text_char(unichar c) {
        return (
            c == 0x20 ||
            c == 0x21 ||
            (c >= 0x23 && c <= 0x2B) ||
            (c >= 0x2D && c <= 0x7E) ||
            c >= 0x80
        );
    }


    public string? line_ending { get; set; default = null; }
    public char field_separator { get; set; default = ','; }

    private GLib.InputStream input;
    private GLib.Cancellable? cancellable;

    private unichar next_char = '\0';
    private uint last_record_length = 0;


    /**
     * Constructs a new CSV file reader.
     *
     * The reader is primed during construction, so the given stream
     * will be read from. As such, an IOError or other error may occur
     * during construction.
     *
     * If the given cancellable is not null, it will be used when
     * performing I/O operations on the given input stream.
     */
    public async Reader(GLib.InputStream input,
                        GLib.Cancellable? cancellable = null)
        throws GLib.Error{
        this.input = new GLib.BufferedInputStream(input);
        this.cancellable = cancellable ?? new GLib.Cancellable();

        // prime the look-ahead
        yield read_char();
    }

    public async string[]? read_record() throws GLib.Error {
        string[]? record = null;
        if (!this.input.is_closed()) {
            record = new string[this.last_record_length];
            int next_field = 0;
            while (true) {
                string field = yield read_field();
                if (next_field < record.length) {
                    record[next_field] = field;
                } else {
                    record += field;
                }
                ++next_field;
                if (this.next_char == this.field_separator) {
                    // skip the field sep
                    yield read_char();
                } else {
                    break;
                }
            }
            if (!this.input.is_closed()) {
                yield read_eol();
            }
        }
        this.last_record_length = record.length;
        return record;
    }

    private async string read_field() throws GLib.Error {
        bool quoted = (this.next_char == '"');
        if (quoted) {
            // skip the quote marker
            yield read_char();
        }

        GLib.StringBuilder buf = new GLib.StringBuilder();
        while (!this.input.is_closed() &&
               (quoted || (
                   this.next_char != this.field_separator &&
                   is_text_char(this.next_char)))) {
            unichar c = yield read_char();
            if (quoted && c == '"') {
                if (this.next_char == '"') {
                    buf.append_c('"');
                    yield read_char();
                } else {
                    quoted = false;
                }
            } else {
                buf.append_unichar(c);
            }
        }
        return buf.str;
    }

    private async void read_eol() throws GLib.Error {
        if (this.line_ending == null || this.line_ending == "") {
            // Don't know what the line ending currently is, so guess
            // it
            unichar c = yield read_char();
            if (c == '\n') {
                this.line_ending = "\n";
            } else if (c == '\r') {
                if (this.next_char == '\n') {
                    // consume it
                    yield read_char();
                    this.line_ending = "\r\n";
                } else {
                    this.line_ending = "\r";
                }
            } else {
                throw new DataError.UNKNOWN_EOL(
                    "Unable to determine end of line character 0x%02x", c
                );
            }
        } else {
            // Known line ending, so check for it
            unichar c;
            for (int i = 0; i < this.line_ending.length; i++) {
                c = yield read_char();
                if (this.line_ending[i] != c) {
                    throw new DataError.EOL_NOT_FOUND(
                        "Unexpected end of line character: 0x%02X", c
                    );
                }
            }
        }
    }

    private async unichar read_char() throws GLib.Error {
        unichar c = this.next_char;

        // allocated on the stack
        uint8 buf[1];
        size_t bytes_read = 0;
        yield this.input.read_all_async(
            buf, GLib.Priority.DEFAULT, this.cancellable, out bytes_read
        );
        if (bytes_read > 0) {
            uint8 next = buf[0];
            if (next == 0x00) {
                throw new DataError.NON_TEXT_DATA("Read null byte");
            }
            if (next <= 0x7F) {
                this.next_char = (unichar) next;
            } else {
                uint to_read = 0;
                if (next >> 5 == UTF8_DOUBLE) {
                    to_read = 1;
                } else if (next >> 4 == UTF8_TRIPLE) {
                    to_read = 2;
                } else if (next >> 3 == UTF8_QUADRUPLE) {
                    to_read = 3;
                } else {
                    throw new DataError.NON_TEXT_DATA("Invalid UTF-8 data");
                }

                uint8 utf[5];
                utf[0] = next;
                utf[to_read + 1] = 0x00;
                for (int i = 0; i < to_read; i++) {
                    yield this.input.read_all_async(
                        buf,
                        GLib.Priority.DEFAULT,
                        this.cancellable,
                        out bytes_read
                    );
                    if (bytes_read == 1 && buf[0] >> 6 == UTF8_TRAILER) {
                        utf[i + 1] = buf[0];
                    } else {
                        utf[i + 1] = 0x00;
                        break;
                    }
                }

                this.next_char = ((string) utf).get_char();
                if (!this.next_char.validate()) {
                    this.next_char = UNICODE_REPLACEMENT_CHAR;
                }
            }
        } else {
            this.next_char = '\0';
            yield this.input.close_async();
        }
        return c;
    }

}