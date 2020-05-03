/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2018, 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Writes IMAP protocol strings to the supplied output stream.
 *
 * Since most IMAP commands are small (with the exception of literal
 * data) this class writes directly, synchronously to the given
 * stream. Thus it is highly desirable that the stream passed to the
 * constructor is buffered, either a {@link
 * GLib.BufferedOutputStream}, or some other type that uses a memory
 * buffer large enough to write a typical command completely without
 * causing disk or network I/O.
 *
 * @see Deserializer
 */
public class Geary.Imap.Serializer : BaseObject {


    private const string EOL = "\r\n";
    private const string SPACE = " ";

    private GLib.OutputStream output;


    public Serializer(GLib.OutputStream output) {
        this.output = output;
    }

    /**
     * Writes a string without quoting.
     *
     * It is the caller's responsibility to ensure that the value is
     * valid to be written as an unquoted string, instead of with
     * quoting or as a literal.
     */
    public void push_unquoted_string(string str,
                                     GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.write_all(str.data, null, cancellable);
    }

    /**
     * Writes a string with quoting.
     *
     * It is the caller's responsibility to ensure that the value is
     * valid to be written as a quoted string, instead of as a
     * literal.
     */
    public void push_quoted_string(string str,
                                   GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        StringBuilder buf = new StringBuilder.sized(str.length + 2);
        buf.append_c('"');
        int index = 0;
        char ch = str[index];
        while (ch != String.EOS) {
            if (ch == '"' || ch == '\\') {
                buf.append_c('\\');
            }
            buf.append_c(ch);
            ch = str[++index];
        }
        buf.append_c('"');
        this.output.write_all(buf.data, null, cancellable);
    }

    /**
     * Writes a single ASCII character.
     *
     * It is the caller's responsibility to ensure that the value is
     * valid to be written as-is.
     */
    public void push_ascii(char ch, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        // allocate array on the stack to avoid mem alloc overhead
        uint8 buf[1] = { ch };
        this.output.write_all(buf, null, cancellable);
    }

    /**
     * Writes a ASCII space character.
     */
    public void push_space(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.write_all(SPACE.data, null, cancellable);
    }

    /**
     * Writes a NIL atom.
     */
    public void push_nil(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.write_all(NilParameter.VALUE.data, null, cancellable);
    }

    /**
     * Writes a CRLF sequence.
     */
    public void push_eol(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.write_all(EOL.data, null, cancellable);
    }

    /**
     * Writes literal data to the output stream.
     */
    public async void push_literal_data(uint8[] buffer,
                                        GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        if (buffer.length > 0) {
            yield this.output.write_all_async(
                buffer,
                Priority.DEFAULT,
                cancellable,
                null
            );
        }
    }

    /**
     * Flushes the output stream, ensuring a command has been sent.
     */
    public async void flush_stream(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield this.output.flush_async(GLib.Priority.DEFAULT, cancellable);
    }

    /**
     * Closes the stream, ensuring a command has been sent.
     */
    public async void close_stream(GLib.Cancellable? cancellable)
        throws GLib.IOError {
        yield this.output.close_async(GLib.Priority.DEFAULT, cancellable);
    }

}
