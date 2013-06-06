/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP string that is not quoted.
 *
 * This class does not check if quoting is required.  Use {@link DataFormat.is_quoting_required}
 * or {@link StringParameter.get_best_for}.
 *
 * The difference between this class and {@link AtomParameter} is that this can be used in any
 * circumstance where a string can (or is) represented without quotes or literal data, whereas an
 * atom has strict definitions about where it's found.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.1]]
 */

public class Geary.Imap.UnquotedStringParameter : Geary.Imap.StringParameter {
    public UnquotedStringParameter(string value) {
        base (value);
    }
    
    /**
     * {@inheritDoc}
     */
    public override async void serialize(Serializer ser) throws Error {
        ser.push_unquoted_string(value);
    }
    
    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return value;
    }
}

