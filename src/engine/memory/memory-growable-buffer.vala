/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An {@link Buffer} that can be grown by appending additional buffer fragments.
 *
 * A buffer can be grown by appending data to it ({@link append}), or by allocating additional space
 * in the internal buffer ({@link allocate}) which can then be trimmed back if not entirely used
 * ({@link trim}).
 */

public class Geary.Memory.GrowableBuffer : Memory.Buffer, Memory.UnownedBytesBuffer,
    Memory.UnownedStringBuffer {
    private static uint8[] NUL_ARRAY = { '\0' };

    private ByteArray? byte_array = new ByteArray();
    private Bytes? bytes = null;

    public override size_t size {
        // account for trailing NUL, which is always kept in place for UnownedStringBuffer
        get {
            if (bytes != null)
                return bytes.length - 1;

            assert(byte_array != null);

            return byte_array.len - 1;
        }
    }

    public override size_t allocated_size {
        get {
            return size;
        }
    }

    public GrowableBuffer() {
        // add NUL for UnownedStringBuffer
        byte_array.append(NUL_ARRAY);
    }

    private Bytes to_bytes() {
        if (bytes != null) {
            assert(byte_array == null);

            return bytes;
        }

        assert(byte_array != null);

        bytes = ByteArray.free_to_bytes(byte_array);
        byte_array = null;

        return bytes;
    }

    private unowned uint8[] get_bytes_no_nul() {
        assert(bytes != null);
        assert(bytes.get_size() > 0);

        return bytes.get_data()[0:bytes.get_size() - 1];
    }

    private ByteArray to_byte_array() {
        if (byte_array != null) {
            assert(bytes == null);

            return byte_array;
        }

        assert(bytes != null);

        byte_array = Bytes.unref_to_array(bytes);
        bytes = null;

        return byte_array;
    }

    private unowned uint8[] get_byte_array_no_nul() {
        assert(byte_array != null);
        assert(byte_array.len > 0);

        return byte_array.data[0:byte_array.len - 1];
    }

    /**
     * Appends the data to the existing GrowableBuffer.
     *
     * It's unwise to append to a GrowableBuffer while outstanding ByteArrays and InputStreams
     * (from {@link get_byte_array} or {@link Buffer.get_input_stream}) are outstanding.
     */
    public void append(uint8[] buffer) {
        if (buffer.length <= 0)
            return;

        to_byte_array();

        // account for existing NUL
        assert(byte_array.len > 0);
        byte_array.set_size(byte_array.len - 1);

        // append buffer and new NUL for UnownedStringBuffer
        byte_array.append(buffer);
        byte_array.append(NUL_ARRAY);
    }

    /**
     * Allocate data within the backing buffer for writing.
     *
     * Any usused bytes in the returned buffer should be returned to the {@link GrowableBuffer}
     * via {@link trim}.
     *
     * It's unwise to write to a GrowableBuffer while outstanding ByteArrays and InputStreams
     * (from {@link get_byte_array} or {@link Buffer.get_input_stream}) are outstanding.  Likewise,
     * it's dangerous to be writing to a GrowableBuffer and in the process call get_bytes() and
     * such.
     */
    public unowned uint8[] allocate(size_t requested_bytes) {
        to_byte_array();

        // existing NUL must be there already
        assert(byte_array.len > 0);

        uint original_bytes = byte_array.len;
        uint new_size = original_bytes + (uint) requested_bytes;

        byte_array.set_size(new_size);
        byte_array.data[new_size - 1] = String.EOS;

        // only return portion request, not including new NUL, but overwriting existing NUL
        unowned uint8[] buffer = byte_array.data[(original_bytes - 1):(new_size - 1)];
        assert(buffer.length == requested_bytes);

        return buffer;
    }

    /**
     * Trim a previously allocated buffer.
     *
     * {@link allocate} returns an internal buffer that may be used for writing.  If the entire
     * buffer is not filled, it should be trimmed with this call.
     *
     * filled_bytes is the number of bytes in the supplied buffer that are used (filled).  The
     * remainder are to be trimmed.
     *
     * trim() can only trim back the last allocation; there is no facility for having multiple
     * outstanding allocations and trimming each back randomly.
     *
     * WARNING: No other call to the GrowableBuffer should be made between allocate() and trim().
     * Requesting {@link get_bytes} and other calls may shift the buffer in memory.
     */
    public void trim(uint8[] allocation, size_t filled_bytes) {
        // TODO: pointer arithmetic to verify that this allocation actually belongs to the
        // ByteArray
        assert(byte_array != null);
        assert(filled_bytes <= allocation.length);

        // don't need to worry about the NUL byte here (unless caller overran buffer, then we
        // have bigger problems)
        byte_array.set_size(byte_array.len - (uint) (allocation.length - filled_bytes));
    }

    /**
     * {@inheritDoc}
     */
    public override Bytes get_bytes() {
        to_bytes();
        assert(bytes.get_size() > 0);

        // don't return trailing nul
        return new Bytes.from_bytes(bytes, 0, bytes.get_size() - 1);
    }

    /**
     * {@inheritDoc}
     */
    public override ByteArray get_byte_array() {
        ByteArray copy = new ByteArray();

        // don't copy trailing NUL
        if (bytes != null) {
            copy.append(get_bytes_no_nul());
        } else {
            assert(byte_array != null);
            copy.append(get_byte_array_no_nul());
        }

        return copy;
    }

    /**
     * {@inheritDoc}
     */
    public override uint8[] get_uint8_array() {
        // because returned array is not unowned, Vala will make a copy
        return to_unowned_uint8_array();
    }

    /**
     * {@inheritDoc}
     */
    public unowned uint8[] to_unowned_uint8_array() {
        // in any case, don't return trailing NUL
        if (bytes != null)
            return get_bytes_no_nul();

        assert(byte_array != null);

        return get_byte_array_no_nul();
    }

    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        // because returned string is not unowned, Vala will make a copy
        return to_unowned_string();
    }

    /**
     * {@inheritDoc}
     */
    public unowned string to_unowned_string() {
        // because of how append() and allocate() ensure a trailing NUL, can convert data to a
        // string without copy-and-append
        if (bytes != null)
            return (string) bytes.get_data();

        assert(byte_array != null);

        return (string) byte_array.data;
    }
}

