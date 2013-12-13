/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A class which can be serialized by {@link Serializer}.
 *
 * Serializer is only capable of serializing basic data types (int, bool, string, etc).  Complex
 * data types must manually serialize their values in their {@link serialize_property} method.
 */

public interface Geary.Persistance.Serializable : Object {
    /**
     * Utility method to return the object's serializable class name (GType name).
     */
    public string serialize_classname() {
        return get_class().get_type().name();
    }
    
    /**
     * Returns the version number of this Object's properties signature.
     *
     * If the properties of the implementing class changes, this value should be incremented.
     */
    public abstract int interface_version();
    
    /**
     * Manual serialization of a property.
     *
     * If {@link Serializer} is incapable of serializing a property, this method is called.
     * The object must either manually serialize the property (use name to determine which) and
     * return true, or return false.
     *
     * In particular, although {@link DataFlavorSerializer} offers methods to serialize integer
     * and string arrays, Serializer is ''unable'' to automatically determine the type of those
     * properties due to limitations of GType, and so the Serializable object must do those itself.
     */
    public virtual bool serialize_property(string name, DataFlavorSerializer serializer) throws Error {
        return false;
    }
    
    /**
     * Manual deserialization of a property.
     *
     * {@link Deserializer} gives the {@link Serializable} object a chance to manually deserialize
     * a property before it attempts to do it automatically.
     *
     * If {@link Serializer} is incapable of serializing a property, this method is called.
     * The object must either manually serialize the property (use name to determine which) and
     * return true, or return false.  Integer and string arrays in particular must be deserialized
     * manually.
     *
     * @see serialize_property
     */
    public virtual bool deserialize_property(string name, DataFlavorDeserializer deserializer) throws Error {
        return false;
    }
}

