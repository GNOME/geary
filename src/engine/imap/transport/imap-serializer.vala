/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Writes serialized IMAP commands to a supplied output stream.
 *
 * Command continuation requires some synchronization between the
 * Serializer and the {@link Deserializer}.  It also requires some
 * queue management.  See {@link push_quoted_string} and {@link
 * next_synchronized_message}.
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

    public void push_ascii(char ch, GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_byte(ch, cancellable);
    }

    public void push_space(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_byte(' ', cancellable);
    }

    public void push_nil(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_string(NilParameter.VALUE, cancellable);
    }

    public void push_eol(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        this.output.put_string("\r\n", cancellable);
    }

    /**
     * Pushes literal data to the output stream.
     */
    public async void push_literal_data(Memory.Buffer buffer,
                                        GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield this.output.splice_async(
            buffer.get_input_stream(),
            OutputStreamSpliceFlags.NONE,
            Priority.DEFAULT,
            cancellable
        );
    }

    /**
     * Flushes the output stream, ensuring a command has been sent.
     */
    public async void flush_stream(GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield this.output.flush_async(Priority.DEFAULT, cancellable);
    }

    public string to_string() {
        return "ser:%s".printf(identifier);
    }

}
