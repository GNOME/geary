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

public enum SerializedType {
    BOOL = 0,
    INT,
    INT64,
    FLOAT,
    DOUBLE,
    UTF8,
    INT_ARRAY,
    UTF8_ARRAY;
    
    public int serialize() {
        return (int) this;
    }
    
    public static SerializedType deserialize(int value) throws Error {
        return (SerializedType) value;
    }
}

