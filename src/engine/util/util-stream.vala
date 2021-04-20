/* Copyright 2016 Software Freedom Conservancy Inc.
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

    /**
     * Adaptor from a GMime stream to a GLib OutputStream.
     */
    public class MimeOutputStream : GMime.Stream {

        GLib.OutputStream dest;
        int64 written = 0;


        public MimeOutputStream(GLib.OutputStream dest) {
            this.dest = dest;
        }

        public override int64 length() {
            // This is a bit of a kludge, but we use it in
            // ImapDB.Attachment
            return this.written;
        }

#if GMIME_STREAM_WRITE_STRING
        public override ssize_t write(string buf, size_t len) {
            try {
                var ret = this.dest.write(buf.data[0:len]);
#else
        public override ssize_t write(uint8[] buf) {
            try {
                var ret = this.dest.write(buf);
#endif
                if (ret > 0) {
                    this.written += ret;
                }
                return ret;
            } catch (IOError err) {
                // Oh well
                return -1;
            }
        }

        public override int close() {
            int ret = -1;
            try {
                ret = this.dest.close() ? 0 : -1;
            } catch (IOError err) {
                // Oh well
            }
            return ret;
        }

        public override int flush () {
            int ret = -1;
            try {
                ret = this.dest.flush() ? 0 : -1;
            } catch (Error err) {
                // Oh well
            }
            return ret;
        }

        public override bool eos () {
            return this.dest.is_closed() || this.dest.is_closing();
        }
    }


}
