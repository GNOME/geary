/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Type information about a serialized value.
 *
 * The integer values for this enumeration are immutable and will not change in the future.
 */

public enum Geary.Persistance.SerializedType {
    BOOL = 0,
    INT,
    INT64,
    FLOAT,
    DOUBLE,
    UTF8,
    INT_ARRAY,
    UTF8_ARRAY;
    
    /**
     * Returns a somewhat human-readable string for serializing a type.
     *
     * The enumerated values (0..n) won't change in the future, but if the {@link DataFlavor}
     * prefers to use a string rather than an integer value to store type information, this and
     * {@link deserialize} are available.
     */
    public unowned string serialize() throws Error {
        if (!is_valid())
            throw new PersistanceError.INVALID("Invalid SerializedType: %d", (int) this);
        
        switch (this) {
            case BOOL:
                return "b";
            
            case INT:
                return "i";
            
            case INT64:
                return "i64";
            
            case FLOAT:
                return "f";
            
            case DOUBLE:
                return "d";
            
            case UTF8:
                return "s";
            
            case INT_ARRAY:
                return "iar";
            
            case UTF8_ARRAY:
                return "sar";
            
            default:
                assert_not_reached();
        }
    }
    
    /**
     * Deserializes a string from {@link serialize} into a {@link SerializedType}.
     */
    public static SerializedType deserialize(string value) throws Error {
        switch (value) {
            case "b":
                return BOOL;
            
            case "i":
                return INT;
            
            case "i64":
                return INT64;
            
            case "f":
                return FLOAT;
            
            case "d":
                return DOUBLE;
            
            case "s":
                return UTF8;
            
            case "iar":
                return INT_ARRAY;
            
            case "sar":
                return UTF8_ARRAY;
            
            default:
                throw new PersistanceError.INVALID("Invalid SerializedType: %d", value);
        }
    }
    
    public bool is_valid() {
        return Numeric.int_in_range_inclusive(this, BOOL, UTF8_ARRAY);
    }
}

