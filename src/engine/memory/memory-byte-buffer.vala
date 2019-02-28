/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Allows for a plain block of bytes to be represented as an {@link Buffer}.
 */

public class Geary.Memory.ByteBuffer : Memory.Buffer, Memory.UnownedBytesBuffer {
    /**
     * {@inheritDoc}
     */
    public override size_t size {
        get {
            return bytes.length;
        }
    }

    /**
     * {@inheritDoc}
     */
    public override size_t allocated_size {
        get {
            return allocated_bytes;
        }
    }

    private Bytes bytes;
    private size_t allocated_bytes;

    /**
     * filled is the number of usable bytes in the supplied buffer, allocated is the total size
     * of the buffer.
     *
     * filled must be less than or equal to the allocated size of the buffer.
     *
     * A copy of the data buffer is made.  See {@link ByteBuffer.ByteBuffer.take} for a no-copy
     * alternative.
     */
    public ByteBuffer(uint8[] data, size_t filled) {
        assert(filled <= data.length);

        bytes = new Bytes(data[0:filled]);
        allocated_bytes = bytes.length;
    }

    /**
     * filled is the number of usable bytes in the supplied buffer, allocated is the total size
     * of the buffer.
     *
     * filled must be less than or equal to the allocated size of the buffer.
     */
    public ByteBuffer.take(owned uint8[] data, size_t filled) {
        assert(filled <= data.length);

        bytes = new Bytes.take(data[0:filled]);
        allocated_bytes = data.length;
    }

    /**
     * Takes ownership and converts a ByteArray to a {@link ByteBuffer}.
     *
     * The ByteArray is freed after this call and should not be used.
     */
    public ByteBuffer.from_byte_array(ByteArray byte_array) {
        bytes = ByteArray.free_to_bytes(byte_array);
        allocated_bytes = bytes.length;
    }

    /**
     * Takes ownership and converts a MemoryOutputStream to a {@link ByteBuffer}.
     *
     * The MemoryOutputStream ''must'' be closed before this call.
     */
    public ByteBuffer.from_memory_output_stream(MemoryOutputStream mouts) {
        assert(mouts.is_closed());

        bytes = mouts.steal_as_bytes();
        allocated_bytes = bytes.length;
    }

    /**
     * {@inheritDoc}
     */
    public override Bytes get_bytes() {
        return bytes;
    }

    /**
     * {@inheritDoc}
     */
    public unowned uint8[] to_unowned_uint8_array() {
        return bytes.get_data();
    }
}

