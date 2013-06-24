/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Serializer asynchronously writes serialized IMAP commands to the supplied output stream via a
 * queue of buffers.
 *
 * Since most IMAP commands are small in size (one line of data, often under 64 bytes), the
 * Serializer writes them to a queue of temporary buffers (interspersed with user-supplied buffers
 * that are intended to be literal data).  The data is only written when {@link flush_async} is
 * invoked.
 *
 * This means that if the caller wants some buffer beyond the steps described above, they should
 * pass in a BufferedOutputStream (or one of its subclasses).  flush_async() will flush the user's
 * OutputStream after writing to it.
 *
 * Command continuation requires some synchronization between the Serializer and the
 * {@link Deserializer}.  It also requires some queue management.  See {@link fast_forward_queue}
 * and {@link next_synchronized_message}.
 *
 * @see Deserializer
 */

public class Geary.Imap.Serializer : BaseObject {
    private class SerializedData {
        public Memory.Buffer buffer;
        public Tag? literal_data_tag;
        
        public SerializedData(Memory.Buffer buffer, Tag? literal_data_tag) {
            this.buffer = buffer;
            this.literal_data_tag = literal_data_tag;
        }
    }
    
    private string identifier;
    private OutputStream outs;
    private ConverterOutputStream couts;
    private MemoryOutputStream mouts;
    private DataOutputStream douts;
    private Geary.Stream.MidstreamConverter midstream = new Geary.Stream.MidstreamConverter("Serializer");
    private Gee.Queue<SerializedData?> datastream = new Gee.LinkedList<SerializedData?>();
    
    public Serializer(string identifier, OutputStream outs) {
        this.identifier = identifier;
        this.outs = outs;
        
        // prepare the ConverterOutputStream (which wraps the caller's OutputStream and allows for
        // midstream conversion)
        couts = new ConverterOutputStream(outs, midstream);
        couts.set_close_base_stream(false);
        
        // prepare the DataOutputStream (which generates buffers for the queue)
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
        douts.set_close_base_stream(false);
    }
    
    public bool install_converter(Converter converter) {
        return midstream.install(converter);
    }
    
    public void push_ascii(char ch) throws Error {
        douts.put_byte(ch, null);
    }
    
    /**
     * Pushes the string to the IMAP server with quoting applied whether required or not.  Returns
     * true if quoting was required.
     */
    public bool push_quoted_string(string str) throws Error {
        string quoted;
        DataFormat.Quoting requirement = DataFormat.convert_to_quoted(str, out quoted);
        
        douts.put_string(quoted);
        
        return (requirement == DataFormat.Quoting.REQUIRED);
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
    
    private void enqueue_current_stream() throws IOError {
        size_t length = mouts.get_data_size();
        if (length <= 0)
            return;
        
        // close before converting to Memory.ByteBuffer
        mouts.close();
        
        SerializedData data = new SerializedData(
            new Memory.ByteBuffer.from_memory_output_stream(mouts), null);
        datastream.add(data);
        
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
        douts.set_close_base_stream(false);
    }
    
    /*
     * Pushes an {link Memory.Buffer} to the serialized stream that must be synchronized
     * with the server before transmission.
     *
     * Literal data may require synchronization with the server and so should only be used when
     * necessary.  See {link DataFormat.is_quoting_required} to test data.
     *
     * The supplied buffer must not be mutated once submitted to the {@link Serializer}.
     *
     * See [[http://tools.ietf.org/html/rfc3501#section-4.3]] and
     * [[http://tools.ietf.org/html/rfc3501#section-7.5]]
     */
    public void push_synchronized_literal_data(Tag tag, Memory.Buffer buffer) throws Error {
        enqueue_current_stream();
        datastream.add(new SerializedData(buffer, tag));
    }
    
    /**
     * Indicates that a complete message has been pushed to the {@link Serializer}.
     *
     * It's important to delineate messages for the Serializer, as it aids in queue management
     * and command continuation (synchronization).
     */
    public void push_end_of_message() throws Error {
        enqueue_current_stream();
        datastream.add(null);
    }
    
    /**
     * Returns the {@link Tag} for the message with the next synchronization message Tag.
     *
     * This can be used to prepare for receiving a command continuation failure before sending
     * the request via {@link flush_async}, as the response could return before that call completes.
     */
    public Tag? next_synchronized_message() {
        foreach (SerializedData? data in datastream) {
            if (data != null && data.literal_data_tag != null)
                return data.literal_data_tag;
        }
        
        return null;
    }
    
    /**
     * Discards all buffers associated with the current message and moves the queue forward to the
     * next one.
     *
     * This is useful when a command continuation is refused by the server and the command must be
     * aborted.
     *
     * Any data currently in the buffer is *not* enqueued, as by definition it has not been marked
     * with {@link push_end_of_message}.
     */
    public void fast_forward_queue() {
        while (!datastream.is_empty) {
            if (datastream.poll() == null)
                break;
        }
    }
    
    /**
     * Push all serialized data and buffers onto the wire.
     *
     * Caller should pass is_synchronized=true if the connection has been synchronized for a command
     * continuation.
     *
     * If synchronize_tag returns non-null, then the flush has not completed.  The connection must
     * wait for the server to send a continuation response before continuing.  When ready, call
     * flush_async() again with is_synchronized set to true.  The tag is supplied to watch for
     * an error condition from the server (which may reject the synchronization request).
     */
    public async void flush_async(bool is_synchronized, out Tag? synchronize_tag,
        Cancellable? cancellable = null) throws Error {
        synchronize_tag = null;
        
        // commit the last buffer to the queue (although this is best done with push_end_message)
        enqueue_current_stream();
        
        // walk the SerializedData queue, pushing each out to the wire unless a synchronization
        // point is encountered
        while (!datastream.is_empty) {
            // see if next data buffer is synchronized
            SerializedData? data = datastream.peek();
            if (data != null && data.literal_data_tag != null && !is_synchronized) {
                // report the Tag that is associated with the continuation
                synchronize_tag = data.literal_data_tag;
                
                // break out to ensure pipe is flushed
                break;
            }
            
            // if not, remove and process
            data = datastream.poll();
            if (data == null) {
                // end of message, move on
                continue;
            }
            
            Logging.debug(Logging.Flag.SERIALIZER, "[%s] %s", to_string(), data.buffer.to_string());
            
            // splice buffer's InputStream directly into OutputStream
            yield couts.splice_async(data.buffer.get_input_stream(), OutputStreamSpliceFlags.NONE,
                Priority.DEFAULT, cancellable);
            
            // if synchronized before, not any more
            is_synchronized = false;
        }
        
        // make sure everything is flushed out now ... some trouble with BufferedOutputStreams
        // here, so flush ConverterOutputStream and its base stream
        yield couts.flush_async(Priority.DEFAULT, cancellable);
        yield couts.base_stream.flush_async(Priority.DEFAULT, cancellable);
    }
    
    public string to_string() {
        return "ser:%s".printf(identifier);
    }
}

