/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents a response to an IMAP continuation request.
 *
 * Do not use this if you need to send literal data as part of a
 * command, add it as a {@link LiteralParameter} to the command
 * instead.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.5]]
 */

public class Geary.Imap.ContinuationParameter : Geary.Imap.Parameter {


    private uint8[] data;


    /**
     * Response to the continuation request.
     *
     * The given data will be sent to the server as-is. It should not
     * contain a trailing EOL.
     */
    public ContinuationParameter(uint8[] data) {
        this.data = data;
    }

    public void serialize_continuation(Serializer ser)
        throws GLib.Error {
        ser.push_unquoted_string(
            new Memory.ByteBuffer.take(this.data, this.data.length).to_string()
        );
        ser.push_eol();
    }

    /** {@inheritDoc} */
    public override void serialize(Serializer ser, Tag tag)
        throws GLib.Error {
        serialize_continuation(ser);
    }

    /** {@inheritDoc} */
    public override string to_string() {
        return new Memory.ByteBuffer.take(this.data, this.data.length).to_string();
    }

}
