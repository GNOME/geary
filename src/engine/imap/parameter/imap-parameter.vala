/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The basic abstraction of a single IMAP parameter that may be serialized and deserialized to and
 * from the network.
 *
 * @see Serializer
 * @see Deserializer
 */

public abstract class Geary.Imap.Parameter : BaseObject {
    /**
     * Returns an appropriate {@link Parameter} for the string.
     *
     * get_for_string() goes from simple to complexity in terms of parameter encoding.  It uses
     * {@link StringParameter.get_best_for} first to attempt to produced an unquoted, then unquoted,
     * string.  (It will also produce a {@link NumberParameter} if appropriate.)  If the string
     * cannot be held in those forms, it returns a {@link LiteralParameter}, which is capable of
     * transmitting 8-bit data.
     */
    public static Parameter get_for_string(string value) {
        try {
            return StringParameter.get_best_for(value);
        } catch (ImapError ierr) {
            return new LiteralParameter(new Memory.StringBuffer(value));
        }
    }

    /**
     * Invoked when this parameter is to be serialized out to the network.
     *
     * This method is intended to be used for serialising IMAP command
     * lines, which are typically short, single lines. Hence this
     * method is not asynchronous since the serialiser will buffer
     * writes to it. Any parameters with large volumes of data to
     * serialise (typically {@link LiteralParameter}) are specially
     * handled by {@link Command} when serialising.
     */
    public abstract void serialize(Serializer ser, GLib.Cancellable cancellable)
        throws GLib.Error;

    /**
     * Returns a representation of the {@link Parameter} suitable for logging and debugging,
     * but should not be relied upon for wire or persistent representation.
     */
    public abstract string to_string();

}
