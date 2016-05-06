/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Interface which allows access to backing data of {@link Memory.Buffer} without transferring
 * ownership, i.e. copying the buffer.
 *
 * The presence of this interface indicates that obtaining access to the backing buffer is cheap
 * (i.e. get_bytes().get_data() will do the same thing, but generating a Bytes object might have
 * a cost).
 *
 * Not all AbstractBuffers can support this call, but if they can, this interface allows for it.
 * The buffers that are returned should ''not'' be modified or freed by the caller.
 */

public interface Geary.Memory.UnownedBytesBuffer : Memory.Buffer {
    /**
     * Returns an unowned pointer of the backing buffer.
     *
     * The returned array should not be modified or freed.
     */
    public abstract unowned uint8[] to_unowned_uint8_array();
}

