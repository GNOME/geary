/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

namespace Stream {

public async void write_all_async(OutputStream outs, uint8[] data, ssize_t offset = 0, int length = -1,
    int priority = GLib.Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
    if (length < 0)
        length = data.length;
    
    if (length == 0)
        return;
    
    if (offset >= length) {
        throw new IOError.INVALID_ARGUMENT("Offset %s outside of buffer length %d", offset.to_string(),
            length);
    }
    
    do {
        offset += yield outs.write_async(data[offset:length], priority, cancellable);
    } while (offset < length);
}

}

