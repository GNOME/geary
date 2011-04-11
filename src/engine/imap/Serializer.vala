/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Serializer {
    private MemoryOutputStream mouts;
    private DataOutputStream douts;
    
    public Serializer() {
        mouts = new MemoryOutputStream(null, realloc, free);
        douts = new DataOutputStream(mouts);
    }
    
    public unowned uint8[] get_content() {
        return mouts.get_data();
    }
    
    public size_t get_content_length() {
        return mouts.get_data_size();
    }
    
    public bool has_content() {
        return get_content_length() > 0;
    }
    
    // TODO: Remove
    public void push_nil() throws Error {
        douts.put_string("nil", null);
    }
    
    // TODO: Remove
    public void push_token(string str) throws Error {
        douts.put_string(str, null);
    }
    
    public void push_string(string str) throws Error {
        douts.put_string(str, null);
    }
    
    public void push_space() throws Error {
        douts.put_byte(' ', null);
    }
    
    public void push_eol() throws Error {
        douts.put_string("\r\n", null);
    }
    
    public void push_literal_data(uint8[] data) throws Error {
        size_t written;
        douts.write_all(data, out written);
        assert(written == data.length);
    }
    
    public void push_input_stream_literal_data(InputStream ins) throws Error {
        douts.splice(ins, OutputStreamSpliceFlags.NONE);
    }
}

