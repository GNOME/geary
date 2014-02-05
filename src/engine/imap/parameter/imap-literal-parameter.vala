/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP literal parameter.
 *
 * Because a literal parameter can hold 8-bit data, this is not a descendent of
 * {@link StringParameter}, although some times literal data is used to store 8-bit text (for
 * example, UTF-8).
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.3]]
 */

public class Geary.Imap.LiteralParameter : Geary.Imap.Parameter {
    private Memory.Buffer buffer;
    
    public LiteralParameter(Memory.Buffer buffer) {
        this.buffer = buffer;
    }
    
    /**
     * Returns the number of bytes in the literal parameter's buffer.
     */
    public size_t get_size() {
        return buffer.size;
    }
    
    /**
     * Returns the literal paremeter's buffer.
     */
    public Memory.Buffer get_buffer() {
        return buffer;
    }
    
    /**
     * Returns the {@link LiteralParameter} as though it had been a {@link StringParameter} on the
     * wire.
     *
     * Note that this does not deal with quoting issues or NIL (which should never be
     * literalized to begin with).  It merely converts the literal data to a UTF-8 string and
     * returns it as a StringParameter.  Hence, the data is being coerced and may be unsuitable
     * for transmitting on the wire.
     */
    public StringParameter coerce_to_string_parameter() {
        return new UnquotedStringParameter(buffer.get_valid_utf8());
    }
    
    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return "{literal/%lub}".printf(get_size());
    }
    
    /**
     * {@inheritDoc}
     */
    public override void serialize(Serializer ser, Tag tag) throws Error {
        ser.push_unquoted_string("{%lu}".printf(get_size()));
        ser.push_eol();
        ser.push_synchronized_literal_data(tag, buffer);
    }
}

