/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Interface which allows access to a backing ByteArray of {@link Memory.Buffer} without
 * transferring ownership, i.e. copying the ByteArray.
 *
 * The presence of this interface indicates that obtaining access to the backing buffer is cheap.
 *
 * Not all AbstractBuffers can support this call, but if they can, this interface allows for it.
 * The ByteArray that is returned should ''not'' be modified or freed by the caller.
 */

public interface Geary.Memory.UnownedByteArrayBuffer : Memory.Buffer {
    /**
     * Returns an unowned pointer to the backing ByteArray.
     *
     * The returned ByteArray should not be modified or freed.
     */
    public abstract unowned ByteArray to_unowned_byte_array();
}

