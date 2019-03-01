/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Allows for a common string to be represented as an {@link Memory.Buffer}.
 */

public class Geary.Memory.StringBuffer : Memory.Buffer, Memory.UnownedStringBuffer,
    Memory.UnownedBytesBuffer {
    public override size_t size {
        get {
            return length;
        }
    }

    public override size_t allocated_size {
        get {
            return length;
        }
    }

    private string str;
    private size_t length;
    private Bytes? bytes = null;

    public StringBuffer(string str) {
        this.str = str;
        length = str.data.length;
    }

    /**
     * {@inheritDoc}
     */
    public override Bytes get_bytes() {
        return (bytes != null) ? bytes : bytes = new Bytes(str.data);
    }

    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return str;
    }

    /**
     * {@inheritDoc}
     */
    public override string get_valid_utf8() {
        return str.validate() ? str : "";
    }

    /**
     * {@inheritDoc}
     */
    public unowned string to_unowned_string() {
        return str;
    }

    /**
     * {@inheritDoc}
     */
    public unowned uint8[] to_unowned_uint8_array() {
        return str.data;
    }
}

