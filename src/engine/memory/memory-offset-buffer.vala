/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A buffer that's simply an offset into an existing buffer.
 */

public class Geary.Memory.OffsetBuffer : Geary.Memory.Buffer, Geary.Memory.UnownedBytesBuffer {
    /**
     * {@inheritDoc}
     */
    public override size_t size { get { return buffer.size - offset; } }
    
    /**
     * {@inheritDoc}
     */
    public override size_t allocated_size { get { return size; } }
    
    private Geary.Memory.Buffer buffer;
    private size_t offset;
    private Bytes? bytes = null;
    
    public OffsetBuffer(Geary.Memory.Buffer buffer, size_t offset) {
        assert(offset < buffer.size);
        this.buffer = buffer;
        this.offset = offset;
    }
    
    /**
     * {@inheritDoc}
     */
    public override Bytes get_bytes() {
        if (bytes == null)
            bytes = new Bytes.from_bytes(buffer.get_bytes(), offset, buffer.size - offset);
        return bytes;
    }
    
    /**
     * {@inheritDoc}
     */
    public unowned uint8[] to_unowned_uint8_array() {
        return get_bytes().get_data();
    }
}
