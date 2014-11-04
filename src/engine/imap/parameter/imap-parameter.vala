/* Copyright 2011-2014 Yorba Foundation
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
     * Invoked when the {@link Parameter} is to be serialized out to the network.
     *
     * The supplied Tag will have (or will be) assigned to the message, so it should be passed
     * to all serialize() calls this call may make.  The {@link Parameter} should not use its own
     * internal Tag object, if it has a reference to one.
     */
    public abstract void serialize(Serializer ser, Tag tag) throws Error;
    
    /**
     * Returns a representation of the {@link Parameter} suitable for logging and debugging,
     * but should not be relied upon for wire or persistent representation.
     */
    public abstract string to_string();
}

