/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An interface to the basic deserializer facilities provided by the {@link DataFlavor} itself.
 *
 * The DataFlavorDeserializer is responsible for maintaining little state, just enough to allow for
 * its methods to be called in roughly any order without issue.  The deserialized state is expected
 * to be held entirely in memory.
 */

public interface Geary.Persistance.DataFlavorDeserializer : BaseObject {
    public abstract string get_classname() throws Error;
    
    public abstract int get_serialized_version() throws Error;
    
    public abstract bool has_value(string name) throws Error;
    
    public abstract SerializedType get_value_type(string name) throws Error;
    
    public abstract bool get_bool(string name) throws Error;
    
    public abstract int get_int(string name) throws Error;
    
    public abstract int64 get_int64(string name) throws Error;
    
    public abstract float get_float(string name) throws Error;
    
    public abstract double get_double(string name) throws Error;
    
    public abstract string get_utf8(string name) throws Error;
    
    public abstract int[] get_int_array(string name) throws Error;
    
    public abstract string[] get_utf8_array(string name) throws Error;
}

