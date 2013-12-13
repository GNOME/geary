/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Serializer turns Objects which implement {@link Serializable} into a serialized byte stream
 * that may be persisted or transmitted and reconstituted later by {@link Deserializer}.
 *
 * The serialized stream the Serializer produces for each object cannot merely be appended together
 * without some control mechanism to separate them (in separate files or database rows, a length
 * marker between each in the stream, etc.)  That is, Deserializer will ''not'' break up an appended
 * stream of serialized objects properly; that is up to the caller to do, and it must call the
 * appropriate deserialization calls for each packet of bytes.
 *
 * Also, the serialized stream contains no metadata indicating which DataFlavor was utilized.  That
 * must be decided by or maintained by the caller via appropriate means.
 */

public class Geary.Persistance.Serializer : BaseObject {
    private DataFlavor flavor;
    
    public Serializer(DataFlavor flavor) {
        this.flavor = flavor;
    }
    
    /**
     * Serialize the supplied Object into a byte stream using the persistance {@link Flavor} given
     * to the {@link Serializer} and written to the OutputStream.
     *
     * The OutputStream is not closed when completed.
     */
    public Geary.Memory.Buffer to_buffer(Serializable sobj) throws Error {
        DataFlavorSerializer serializer = flavor.create_serializer(sobj);
        
        serialize_properties(serializer, sobj);
        
        return serializer.commit();
    }
    
    private void serialize_properties(DataFlavorSerializer serializer, Serializable sobj) throws Error {
        foreach (ParamSpec param_spec in sobj.get_class().list_properties()) {
            if (!is_serializable(param_spec, true))
                continue;
            
            Value value = Value(param_spec.value_type);
            sobj.get_property(param_spec.name, ref value);
            
            if (param_spec.value_type == typeof(bool)) {
                serializer.set_bool(param_spec.name, (bool) value);
            } else if (param_spec.value_type == typeof(int)) {
                serializer.set_int(param_spec.name, (int) value);
            } else if (param_spec.value_type == typeof(int64)) {
                serializer.set_int64(param_spec.name, (int64) value);
            } else if (param_spec.value_type == typeof(float)) {
                serializer.set_float(param_spec.name, (float) value);
            } else if (param_spec.value_type == typeof(double)) {
                serializer.set_double(param_spec.name, (double) value);
            } else if (param_spec.value_type == typeof(string)) {
                serializer.set_utf8(param_spec.name, (string) value);
            } else if (!sobj.serialize_property(param_spec.name, serializer)) {
                debug("WARNING: %s type %s not supported by Serializer", param_spec.name,
                    param_spec.value_type.name());
            }
        }
    }
}


