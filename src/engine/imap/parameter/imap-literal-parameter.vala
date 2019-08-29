/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP literal parameter.
 *
 * Because a literal parameter can hold 8-bit data, this is not a
 * descendent of {@link StringParameter}, although some times literal
 * data is used to store 8-bit text (for example, UTF-8).
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.3]]
 */

public class Geary.Imap.LiteralParameter : Geary.Imap.Parameter {


    /** The value of the literal parameter. */
    public Memory.Buffer value { get; private set; }


    public LiteralParameter(Memory.Buffer value) {
        this.value = value;
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
        return new UnquotedStringParameter(this.value.get_valid_utf8());
    }

    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return "{literal/%lub}".printf(this.value.size);
    }

    /**
     * {@inheritDoc}
     */
    public override void serialize(Serializer ser, GLib.Cancellable cancellable)
        throws GLib.Error {
        ser.push_unquoted_string("{%lu}".printf(this.value.size), cancellable);
        ser.push_eol(cancellable);
    }

}
