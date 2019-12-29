/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Writes IMAP protocol strings to a supplied output stream.
 *
 * This class uses a {@link GLib.DataOutputStream} for writing strings
 * to the given stream. Since that does not support asynchronous
 * writes, it is highly desirable that the stream passed to this class
 * is a {@link GLib.BufferedOutputStream}, or some other type that
 * uses a memory buffer large enough to write a typical command
 * completely without causing disk or network I/O.
 *
 * @see Deserializer
 */
public class Geary.Imap.Serializer : BaseObject {


    private string identifier;
    private GLib.DataOutputStream output;


    public Serializer(string identifier, GLib.OutputStream output) {
        this.identifier = identifier;
        this.output = new GLib.DataOutputStream(output);
        this.output.set_close_base_stream(false);
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
        this.output.put_string(str, cancellable);
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
        this.output.put_byte('"');
        int index = 0;
        char ch = str[index];
        while (ch != String.EOS) {
            if (ch == '"' || ch == '\\') {
                this.output.put_byte('\\');
            }
            this.output.put_byte(ch);
            ch = str[++index];
        }
        this.output.put_byte('"');
    }

    /**
     * Writes a single ASCII character.
     *
     * It is the caller's responsibility to ensure that the value is
     * valid to be written as-is.
     */
    public void push_ascii(char ch, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_byte(ch, cancellable);
    }

    /**
     * Writes a single ASCII space character.
     */
    public void push_space(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_byte(' ', cancellable);
    }

    /**
     * Writes a NIL atom.
     */
    public void push_nil(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_string(NilParameter.VALUE, cancellable);
    }

    /**
     * Writes a CRLF sequence.
     */
    public void push_eol(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_string("\r\n", cancellable);
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

    /**
     * Returns a string representation for debugging.
     */
    public string to_string() {
        return "ser:%s".printf(identifier);
    }

}
