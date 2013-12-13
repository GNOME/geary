/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A simple implementation to allow Object persistance in a GKeyFile format.
 *
 * Because this DataFlavor maintains no instance-specific state, it's a singleton class.  Use
 * {@link instance} to retrieve the global instance.
 */

public class Geary.Persistance.Flavor.GKeyFile : BaseObject, Geary.Persistance.DataFlavor {
    private const string VERSION_NAME = "__version__";
    
    private class KeyFileSerializer :  BaseObject, DataFlavorSerializer {
        private string groupname;
        private KeyFile keyfile = new KeyFile();
        
        public KeyFileSerializer(Serializable sobj) {
            groupname = sobj.serialize_classname();
            
            // set the object version number
            keyfile.set_integer(groupname, VERSION_NAME, sobj.serialize_version());
        }
        
        public void set_bool(string name, bool b) {
            keyfile.set_integer(groupname, typename(name), SerializedType.BOOL.serialize());
            keyfile.set_boolean(groupname, name, b);
        }
        
        public void set_int(string name, int i) {
            keyfile.set_integer(groupname, typename(name), SerializedType.INT.serialize());
            keyfile.set_integer(groupname, name, i);
        }
        
        public void set_int64(string name, int64 i64) {
            keyfile.set_integer(groupname, typename(name), SerializedType.INT64.serialize());
            keyfile.set_int64(groupname, name, i64);
        }
        
        public void set_float(string name, float f) {
            keyfile.set_integer(groupname, typename(name), SerializedType.FLOAT.serialize());
            keyfile.set_double(groupname, name, f);
        }
        
        public void set_double(string name, double d) {
            keyfile.set_integer(groupname, typename(name), SerializedType.DOUBLE.serialize());
            keyfile.set_double(groupname, name, d);
        }
        
        public void set_utf8(string name, string utf8) {
            keyfile.set_integer(groupname, typename(name), SerializedType.UTF8.serialize());
            keyfile.set_string(groupname, name, utf8);
        }
        
        public void set_int_array(string name, int[] iar) {
            keyfile.set_integer(groupname, typename(name), SerializedType.INT_ARRAY.serialize());
            keyfile.set_integer_list(groupname, name, iar);
        }
        
        public void set_utf8_array(string name, string[] utf8ar) {
            keyfile.set_integer(groupname, typename(name), SerializedType.UTF8_ARRAY.serialize());
            keyfile.set_string_list(groupname, name, utf8ar);
        }
        
        public Memory.Buffer commit() throws Error {
            return new Memory.StringBuffer(keyfile.to_data());
        }
    }
    
    private class KeyFileDeserializer : BaseObject, DataFlavorDeserializer {
        private string groupname;
        private KeyFile keyfile = new KeyFile();
        
        public KeyFileDeserializer(Geary.Memory.Buffer buffer) throws Error {
            string str = buffer.to_string();
            keyfile.load_from_data(str, str.length, KeyFileFlags.NONE);
            
            groupname = keyfile.get_start_group();
        }
        
        public string get_classname() {
            return groupname;
        }
        
        public int get_serialized_version() throws Error {
            return keyfile.get_integer(groupname, VERSION_NAME);
        }
        
        public bool has_value(string name) throws Error {
            return keyfile.has_key(groupname, name);
        }
        
        public SerializedType get_value_type(string name) throws Error {
            return SerializedType.deserialize(keyfile.get_integer(groupname, typename(name)));
        }
        
        public bool get_bool(string name) throws Error {
            return keyfile.get_boolean(groupname, name);
        }
        
        public int get_int(string name) throws Error {
            return keyfile.get_integer(groupname, name);
        }
        
        public int64 get_int64(string name) throws Error {
            return keyfile.get_int64(groupname, name);
        }
        
        public float get_float(string name) throws Error {
            return (float) keyfile.get_double(groupname, name);
        }
        
        public double get_double(string name) throws Error {
            return keyfile.get_double(groupname, name);
        }
        
        public string get_utf8(string name) throws Error {
            return keyfile.get_string(groupname, name);
        }
        
        public int[] get_int_array(string name) throws Error {
            return keyfile.get_integer_list(groupname, name);
        }
        
        public string[] get_utf8_array(string name) throws Error {
            return keyfile.get_string_list(groupname, name);
        }
    }
    
    private static GKeyFile? _instance = null;
    /**
     * The global instance of GKeyFile.
     */
    public static GKeyFile instance {
        get {
            return (_instance != null) ? _instance : _instance = new GKeyFile();
        }
    }
    
    public string name {
        get {
            return "GKeyFile";
        }
    }
    
    private GKeyFile() {
    }
    
    private static string typename(string name) {
        return "__t_%s__".printf(name);
    }
    
    internal DataFlavorSerializer create_serializer(Serializable sobj) {
        return new KeyFileSerializer(sobj);
    }
    
    internal DataFlavorDeserializer create_deserializer(Geary.Memory.Buffer buffer) throws Error {
        return new KeyFileDeserializer(buffer);
    }
}

