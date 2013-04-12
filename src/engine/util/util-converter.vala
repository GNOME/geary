/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.MidstreamConverter : BaseObject, Converter {
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
                debug("%s read/written: %s/%s (%ld%%)", name, converted_bytes_read.to_string(),
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
