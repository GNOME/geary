/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP quoted string.
 *
 * This class does not check if quoting is required.  Use {@link DataFormat.is_quoting_required}
 * or {@link StringParameter.get_best_for}.
 *
 * {@link Deserializer} will never generate this {@link Parameter}.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.3]].
 */

public class Geary.Imap.QuotedStringParameter : Geary.Imap.StringParameter {
    public QuotedStringParameter(string value) {
        base (value);
    }
    
    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return "\"%s\"".printf(value);
    }
    
    /**
     * {@inheritDoc}
     */
    public override async void serialize(Serializer ser) throws Error {
        ser.push_quoted_string(value);
    }
}

