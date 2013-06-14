/* Copyright 2011-2013 Yorba Foundation
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
     * Invoked when the {@link Parameter} is to be serialized out to the network.
     */
    public abstract async void serialize(Serializer ser) throws Error;
    
    /**
     * Returns a representation of the {@link Parameter} suitable for logging and debugging,
     * but should not be relied upon for wire or persistent representation.
     */
    public abstract string to_string();
}

