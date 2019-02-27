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


    public class MidstreamConverter : BaseObject, Converter {
        public uint64 total_bytes_read { get; private set; default = 0; }
        public uint64 total_bytes_written { get; private set; default = 0; }
        public uint64 converted_bytes_read { get; private set; default = 0; }
        public uint64 converted_bytes_written { get; private set; default = 0; }

        public bool log_performance { get; set; default = false; }

        private string name;
        private Converter? converter = null;

        public MidstreamConverter(string name) {
            this.name = name;
        }

        public bool install(Converter converter) {
            if (this.converter != null)
                return false;

            this.converter = converter;

            return true;
        }

        public ConverterResult convert(uint8[] inbuf, uint8[] outbuf, ConverterFlags flags,
                                       out size_t bytes_read, out size_t bytes_written) throws Error {
            if (converter != null) {
                ConverterResult result = converter.convert(inbuf, outbuf, flags, out bytes_read, out bytes_written);

                total_bytes_read += bytes_read;
                total_bytes_written += bytes_written;

                converted_bytes_read += bytes_read;
                converted_bytes_written += bytes_written;

                if (log_performance && (bytes_read > 0 || bytes_written > 0)) {
                    double pct = (converted_bytes_read > converted_bytes_written)
                    ? (double) converted_bytes_written / (double) converted_bytes_read
                    : (double) converted_bytes_read / (double) converted_bytes_written;
                    debug("%s read/written: %s/%s (%lld%%)", name, converted_bytes_read.to_string(),
                          converted_bytes_written.to_string(), (long) (pct * 100.0));
                }

                return result;
            }

            // passthrough
            size_t copied = size_t.min(inbuf.length, outbuf.length);
            if (copied > 0)
                GLib.Memory.copy(outbuf, inbuf, copied);

            bytes_read = copied;
            bytes_written = copied;

            total_bytes_read += copied;
            total_bytes_written += copied;

            if ((flags & ConverterFlags.FLUSH) != 0)
                return ConverterResult.FLUSHED;

            if ((flags & ConverterFlags.INPUT_AT_END) != 0)
                return ConverterResult.FINISHED;

            return ConverterResult.CONVERTED;
        }

        public void reset() {
            if (converter != null)
                converter.reset();
        }
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

        public override ssize_t write(string buf, size_t len) {
            ssize_t ret = -1;
            try {
                ret = this.dest.write(buf.data[0:len]);
                this.written += len;
            } catch (IOError err) {
                // Oh well
            }
            return ret;
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
