/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP atom.
 *
 * This class does not check if quoting is required.  Use {@link DataFormat.is_quoting_required}
 * or {@link StringParameter.get_best_for}.
 *
 * See {@link StringParameter} for a note about class hierarchy.  In particular, note that
 * [@link Deserializer} will not create this type of {@link Parameter} because it's unable to
 * deduce if a string is an atom or a string from syntax alone.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.1]]
 */
public class Geary.Imap.AtomParameter : Geary.Imap.UnquotedStringParameter {

    public AtomParameter(string value) {
        base (value);
    }

    /**
     * {@inheritDoc}
     */
    public override void serialize(Serializer ser, GLib.Cancellable cancellable)
        throws GLib.Error {
        ser.push_unquoted_string(ascii);
    }

}
