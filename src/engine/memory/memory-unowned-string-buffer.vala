/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Interface which allows access to backing string of {@link Memory.Buffer} without transferring
 * ownership, i.e. copying the string.
 *
 * The presence of this interface indicates that obtaining access to the backing string is cheap.
 *
 * Not all AbstractBuffers can support this call, but if they can, this interface allows for it.
 * The buffers that are returned should ''not'' be modified or freed by the caller.
 */

public interface Geary.Memory.UnownedStringBuffer : Memory.Buffer {
    /**
     * Returns an unowned string version of the backing buffer.
     *
     * The returned string should not be modified or freed.
     */
    public abstract unowned string to_unowned_string();

}
