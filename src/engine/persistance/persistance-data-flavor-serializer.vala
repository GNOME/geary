/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An interface to the basic serializer facilities provided by the {@link DataFlavor} itself.
 *
 * The DataFlavorSerializer is responsible for maintaining little state, just enough to allow for
 * its methods to be called in roughly any order without issue.  The serialized state is expected
 * to be created in memory and returned when {@link commit} is invoked.
 */

public interface Geary.Persistance.DataFlavorSerializer : BaseObject {
    public abstract void set_bool(string name, bool b);
    
    public abstract void set_int(string name, int i);
    
    public abstract void set_int64(string name, int64 i64);
    
    public abstract void set_float(string name, float f);
    
    public abstract void set_double(string name, double d);
    
    public abstract void set_utf8(string name, string utf8);
    
    public abstract void set_int_array(string name, int[] iar);
    
    public abstract void set_utf8_array(string name, string[] utf8ar);
    
    /**
     * Returns the serialized byte stream as a {@link Geary.Memory.Buffer}.
     *
     * The DataFlavorSerializer is not required to reset its state after this call.  It should
     * expect to be discarded soon after commit() is invoked.
     */
    internal abstract Geary.Memory.Buffer commit() throws Error;
}

