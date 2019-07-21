/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Represents an interface to a variety of backing buffers.
 *
 * A Buffer may be an in-memory or on-disk block of bytes.  Buffer allows for a
 * uniform interface to these blocks and makes it easy to move them around and avoiding copies.
 *
 * Questions of mutability are left to the implementation and users of Buffer.  In general,
 * AbstractBuffers should be built and modified before allowing other callers to access it.
 *
 * @see ByteBuffer
 * @see EmptyBuffer
 * @see GrowableBuffer
 * @see StringBuffer
 * @see UnownedStringBuffer
 * @see UnownedBytesBuffer
 */

public abstract class Geary.Memory.Buffer : BaseObject {
    /**
     * Returns the number of valid (usable) bytes in the buffer.
     */
    public abstract size_t size { get; }

    /**
     * Returns the number of bytes allocated (usable and unusable) for the buffer.
     */
    public abstract size_t allocated_size { get; }

    /**
     * Returns a Bytes object holding the buffer's contents.
     *
     * Since Bytes is immutable, the caller will need to make its own copy if it wants to modify
     * the data.
     */
    public abstract Bytes get_bytes();

    /**
     * Returns an InputStream that can read the buffer in its current entirety.
     *
     * Note that the InputStream may share its memory buffer(s) with the Buffer but does
     * not hold references to them or the Buffer itself.  Thus, the Buffer should
     * only be destroyed after all InputStreams are destroyed or exhausted.
     *
     * The base class implementation uses {@link get_bytes} to create the InputStream.  Subclasses
     * should look for more optimal implementations.
     */
    public virtual InputStream get_input_stream() {
        return new MemoryInputStream.from_bytes(get_bytes());
    }

    /**
     * Returns a ByteArray storing the buffer in its entirety.
     *
     * A copy of the backing buffer is returned.
     *
     * The base class implementation uses {@link get_bytes} to create the InputStream.  Subclasses
     * should look for more optimal implementations.
     */
    public virtual ByteArray get_byte_array() {
        ByteArray byte_array = new ByteArray();
        byte_array.append(get_bytes().get_data());

        return byte_array;
    }

    /**
     * Returns an array of uint8 storing the buffer in its entirety.
     *
     * A copy of the backing buffer is returned.
     *
     * The base class implementation uses {@link get_bytes} to create the InputStream.  Subclasses
     * should look for more optimal implementations.
     *
     * @see UnownedBytesBuffer
     */
    public virtual uint8[] get_uint8_array() {
        return get_bytes().get_data();
    }

    /**
     * Returns a copy of the contents of the buffer as though it was a null terminated string.
     *
     * The base class implementation uses {@link get_bytes} to create the InputStream.  Subclasses
     * should look for more optimal implementations.
     *
     * No validation is made on the string.  See {@link get_valid_utf8}.
     *
     * @see UnownedStringBuffer
     */
    public virtual string to_string() {
        uint8[] buffer = get_uint8_array();
        buffer += (uint8) '\0';

        return (string) buffer;
    }

    /**
     * Returns a copy of the contents of the buffer as a UTF-8 string.
     *
     * The base class implementation uses {@link to_string} to create
     * the string and and {@link string.make_valid} to perform the
     * validation. Subclasses should look for more optimal
     * implementations.
     */
    public virtual string get_valid_utf8() {
        return to_string().make_valid();
    }

}
