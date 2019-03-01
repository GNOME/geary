/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

//extern Bytes *g_bytes_new_with_free_func(void *data, size_t size, DestroyNotify destroy, void *user);

/**
 * Makes a file available as a {@link Memory.Buffer}.
 */

public class Geary.Memory.FileBuffer : Memory.Buffer, Memory.UnownedBytesBuffer {
    private File file;
    private MappedFile mmap;

    public override size_t size {
        get {
            return mmap.get_length();
        }
    }

    public override size_t allocated_size {
        get {
            return mmap.get_length();
        }
    }

    /**
     * The File is immediately opened when this is called.
     */
    public FileBuffer(File file, bool readonly) throws Error {
        if (file.get_path() == null)
            throw new IOError.NOT_FOUND("File for Geary.Memory.FileBuffer not found");

        this.file = file;
        mmap = new MappedFile(file.get_path(), !readonly);
    }

    public override Bytes get_bytes() {
        return Bytes.new_with_owner(to_unowned_uint8_array(), mmap);
    }

    public unowned uint8[] to_unowned_uint8_array() {
        unowned uint8[] buffer = (uint8[]) mmap.get_contents();
        buffer.length = (int) mmap.get_length();

        return buffer;
    }
}

