/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The representation of IMAP's NIL value.
 *
 * Note that NIL 'represents the non-existence of a particular data item that is represented as a
 * string or parenthesized list, as distinct from the empty string "" or the empty parenthesized
 * list () ... NIL is never used for any data item which takes the form of an atom."
 *
 * Since there's only one form of a NilParameter, it should be retrieved via the {@link instance}
 * property.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-4.5]]
 */

public class Geary.Imap.NilParameter : Geary.Imap.Parameter {
    public const string VALUE = "NIL";

    private static NilParameter? _instance = null;
    public static NilParameter instance {
        get {
             if (_instance == null)
                _instance = new NilParameter();

            return _instance;
        }
    }

    private NilParameter() {
    }

    /**
     * See note at {@link NilParameter} for comparison rules of "NIL".
     *
     * In particular, this should not be used when expecting an atom.  A mailbox name of NIL
     * means that the mailbox is actually named NIL and does not represent an empty string or empty
     * list.
     */
    public static bool is_nil(StringParameter stringp) {
        return stringp.equals_ci(VALUE);
    }

    /**
     * {@inheritDoc}
     */
    public override void serialize(Serializer ser, GLib.Cancellable cancellable)
        throws GLib.Error {
        ser.push_nil(cancellable);
    }

    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return VALUE;
    }

}
