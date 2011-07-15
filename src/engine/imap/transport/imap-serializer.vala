/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * The Serializer asynchronously writes serialized IMAP commands to the supplied output stream.
 * Since most IMAP commands are small in size (one line of data, often under 64 bytes), the
 * Serializer writes them to a temporary buffer, only writing to the actual stream when literal data
 * is written (which can often be large and coming off of disk) or commit_async() is called, which
 * should be invoked when convenient, to prevent the buffer from growing too large.
 *
 * Because of this situation, the serialized commands will not necessarily reach the output stream
 * unless commit_async() is called, which pushes the in-memory bytes to it.  Since the
 * output stream itself may be buffered, flush_async() should be called to verify the bytes have
 * reached the wire.
 * 
 * flush_async() implies commit_async(), but the reverse is not true.
 */

public class Geary.Imap.Serializer {
    private OutputStream outs;
    private MemoryOutputStream mouts;
    private DataOutputStream douts;
    
    public Serializer(OutputStream outs) {
        this.outs = outs;
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
    }
    
    public void push_ascii(char ch) throws Error {
        douts.put_byte(ch, null);
    }
    
    public void push_string(string str) throws Error {
        // see if need to convert to quoted string, only emitting it if required
        switch (DataFormat.is_quoting_required(str)) {
            case DataFormat.Quoting.OPTIONAL:
                douts.put_string(str);
            break;
            
            case DataFormat.Quoting.REQUIRED:
                string quoted;
                DataFormat.Quoting requirement = DataFormat.convert_to_quoted(str, out quoted);
                assert(requirement == DataFormat.Quoting.REQUIRED);
                
                douts.put_string(quoted);
            break;
            
            case DataFormat.Quoting.UNALLOWED:
            default:
                // TODO: Not handled currently
                assert_not_reached();
        }
    }
    
    /**
     * This will push the string to IMAP as-is.  Use only if you absolutely know what you're doing.
     */
    public void push_unquoted_string(string str) throws Error {
        douts.put_string(str);
    }
    
    public void push_space() throws Error {
        douts.put_byte(' ', null);
    }
    
    public void push_nil() throws Error {
        douts.put_string(NilParameter.VALUE, null);
    }
    
    public void push_eol() throws Error {
        douts.put_string("\r\n", null);
    }
    
    public async void push_input_stream_literal_data_async(InputStream ins,
        int priority = Priority.DEFAULT, Cancellable? cancellable = null) throws Error {
        // commit the in-memory buffer to the output stream
        yield commit_async(priority, cancellable);
        
        // splice the literal data directly to the output stream
        yield outs.splice_async(ins, OutputStreamSpliceFlags.NONE, priority, cancellable);
    }
    
    // commit_async() takes the stored (in-memory) serialized data and writes it asynchronously
    // to the wrapped OutputStream.  Note that this is *not* a flush, as it's possible the
    // serialized data will be stored in a buffer in the OutputStream.  Use flush_async() to force
    // data onto the wire.
    public async void commit_async(int priority = Priority.DEFAULT, Cancellable? cancellable = null)
        throws Error {
        size_t length = mouts.get_data_size();
        if (length == 0)
            return;
        
        ssize_t index = 0;
        do {
            index += yield outs.write_async(mouts.get_data()[index:length], priority, cancellable);
        } while (index < length);
        
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
    }
    
    // This pushes all serialized data onto the wire.  This calls commit_async() before 
    // flushing.
    public async void flush_async(int priority = Priority.DEFAULT, Cancellable? cancellable = null)
        throws Error {
        yield commit_async(priority, cancellable);
        yield outs.flush_async(priority, cancellable);
    }
}

