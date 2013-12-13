/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An interface a data flavor (some scheme for persistance of data) must implement to be usable
 * by {@link Serializer}.
 */

public interface Geary.Persistance.DataFlavor : BaseObject {
    /**
     * Human-readable name for the {@link DataFlavor}, i.e. "KeyFile" or "JSON".
     */
    public abstract string name { get; }
    
    /**
     * Create a new {@link DataFlavorSerializer} for the {@link Serializable} object.
     *
     * The DataFlavorSerializer is not responsible for holding a reference to the Serializable,
     * although it may.
     */
    internal abstract DataFlavorSerializer create_serializer(Serializable sobj);
    
    internal abstract DataFlavorDeserializer create_deserializer(Geary.Memory.Buffer buffer) throws Error;
}

