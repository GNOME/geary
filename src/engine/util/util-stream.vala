/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Geary.Stream {

/**
 * Provides an asynchronous version of OutputStream.write_all().
 */
public async void write_all_async(OutputStream outs, Memory.Buffer buffer, Cancellable? cancellable)
    throws Error {
    if (buffer.size == 0)
        return;
    
    // use an unowned bytes buffer whenever possible
    Bytes? bytes = null;
    unowned uint8[] data;
    Memory.UnownedBytesBuffer? unowned_bytes = buffer as Memory.UnownedBytesBuffer;
    if (unowned_bytes != null) {
        data = unowned_bytes.to_unowned_uint8_array();
    } else {
        // hold the reference to the Bytes object until finished
        bytes = buffer.get_bytes();
        data = bytes.get_data();
    }
    
    ssize_t offset = 0;
    do {
        offset += yield outs.write_async(data[offset:data.length], Priority.DEFAULT, cancellable);
    } while (offset < data.length);
}

/**
 * Asynchronously writes the entire string to the OutputStream.
 */
public async void write_string_async(OutputStream outs, string? str, Cancellable? cancellable)
    throws Error {
    if (!String.is_empty(str))
        yield write_all_async(outs, new Memory.StringBuffer(str), cancellable);
}

}

