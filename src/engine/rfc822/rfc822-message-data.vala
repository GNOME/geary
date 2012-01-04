/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * RFC822.MessageData represents a base class for all the various elements that may be present in
 * an RFC822 message header.  Note that some common elements (such as MailAccount) are not
 * MessageData because they exist in an RFC822 header in list (i.e. multiple email addresses) form.
 */

public interface Geary.RFC822.MessageData : Geary.Common.MessageData {
}

public class Geary.RFC822.MessageID : Geary.Common.StringMessageData, Geary.RFC822.MessageData {
    public MessageID(string value) {
        base (value);
    }
}

/**
 * A Message-ID list stores its IDs from earliest to latest.
 */
public class Geary.RFC822.MessageIDList : Geary.Common.StringMessageData, Geary.RFC822.MessageData {
    public Gee.List<MessageID>? list { get; private set; }
    
    public MessageIDList(string value) {
        base (value);
        
        string[] ids = value.split_set(" \n\r\t");
        foreach (string id in ids) {
            if (String.is_empty(id))
                continue;
            
            // Have seen some mailers use commas between Message-IDs, meaning that the standard
            // whitespace tokenizer is not sufficient; however, can't add the comma (or every other
            // delimiter that mailers dream up) because it may be used within a Message-ID.  The
            // only guarantee made of a Message-ID is that it's surrounded by angle brackets, so
            // mark anything not an angle bracket as a space and strip
            //
            // NOTE: Seen at least one spamfilter mailer that imaginatively uses parens instead of
            // angle brackets for its Message-IDs; accounting for that as well here.
            int start = id.index_of_char('<');
            if (start < 0)
                start = id.index_of_char('(');
            
            int end = id.last_index_of_char('>');
            if (end < 0)
                end = id.last_index_of_char(')');
            
            // if either end not found or the end comes before the beginning, invalid Message-ID
            if (start < 0 || end < 0 || (start >= end)) {
                debug("Invalid Message-ID found: \"%s\"", id);
                
                continue;
            }
            
            // take out the valid slice of the string
            string valid = id.slice(start, end + 1);
            assert(!String.is_empty(valid));
            
            if (id != valid)
                debug("Corrected Message-ID: \"%s\" -> \"%s\"", id, valid);
            
            if (list == null)
                list = new Gee.ArrayList<MessageID>();
            
            list.add(new MessageID(valid));
        }
    }
}

public class Geary.RFC822.Date : Geary.RFC822.MessageData, Geary.Common.MessageData, Equalable, Hashable {
    public string original { get; private set; }
    public DateTime value { get; private set; }
    public time_t as_time_t { get; private set; }
    
    public Date(string iso8601) throws ImapError {
        as_time_t = GMime.utils_header_decode_date(iso8601, null);
        if (as_time_t == 0)
            throw new ImapError.PARSE_ERROR("Unable to parse \"%s\": not ISO-8601 date", iso8601);
        
        value = new DateTime.from_unix_local(as_time_t);
        original = iso8601;
    }
    
    public virtual bool equals(Equalable e) {
        RFC822.Date? other = e as RFC822.Date;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return value.equal(other.value);
    }
    
    public virtual uint to_hash() {
        return value.hash();
    }
    
    public override string to_string() {
        return original;
    }
}

public class Geary.RFC822.Size : Geary.Common.LongMessageData, Geary.RFC822.MessageData {
    public Size(long value) {
        base (value);
    }
}

public class Geary.RFC822.Subject : Geary.Common.StringMessageData, Geary.RFC822.MessageData {
    public string original { get; private set; }
    
    public Subject(string value) {
        base (GMime.utils_header_decode_text(value));
        original = value;
    }
}

public class Geary.RFC822.Header : Geary.Common.BlockMessageData, Geary.RFC822.MessageData {
    private GMime.Message? message = null;
    private string[]? names = null;
    
    public Header(Geary.Memory.AbstractBuffer buffer) {
        base ("RFC822.Header", buffer);
    }
    
    private unowned GMime.HeaderList get_headers() throws RFC822Error {
        if (message != null)
            return message.get_header_list();
        
        GMime.Parser parser = new GMime.Parser.with_stream(
            new GMime.StreamMem.with_buffer(buffer.get_array()));
        parser.set_respect_content_length(false);
        parser.set_scan_from(false);
        
        message = parser.construct_message();
        if (message == null)
            throw new RFC822Error.INVALID("Unable to parse RFC 822 headers");
        
        return message.get_header_list();
    }
    
    public string? get_header(string name) throws RFC822Error {
        return get_headers().get(name);
    }
    
    public string[] get_header_names() throws RFC822Error {
        if (names != null)
            return names;
        
        names = new string[0];
        
        unowned GMime.HeaderIter iter;
        if (!get_headers().get_iter(out iter))
            return names;
        
        do {
            names += iter.get_name();
        } while (iter.next());
        
        return names;
    }
}

public class Geary.RFC822.Text : Geary.Common.BlockMessageData, Geary.RFC822.MessageData {
    public Text(Geary.Memory.AbstractBuffer buffer) {
        base ("RFC822.Text", buffer);
    }
}

public class Geary.RFC822.Full : Geary.Common.BlockMessageData, Geary.RFC822.MessageData {
    public Full(Geary.Memory.AbstractBuffer buffer) {
        base ("RFC822.Full", buffer);
    }
}

// Used for decoding preview text.
public class Geary.RFC822.PreviewText : Geary.RFC822.Text {
    public PreviewText(Geary.Memory.AbstractBuffer _buffer, Geary.Memory.AbstractBuffer? 
        preview_header = null) {
        
        Geary.Memory.AbstractBuffer buffer = _buffer;
        
        if (preview_header != null) {
            string? charset = null;
            string? encoding = null;
            
            // Parse the header.
            GMime.Stream header_stream = new GMime.StreamMem.with_buffer(
                preview_header.get_array());
            GMime.Parser parser = new GMime.Parser.with_stream(header_stream);
            GMime.Part? part = parser.construct_part() as GMime.Part;
            if (part != null) {
                charset = part.get_content_type_parameter("charset");
                encoding = part.get_header("Content-Transfer-Encoding");
            }
            
            GMime.StreamMem input_stream = new GMime.StreamMem.with_buffer(buffer.get_array());
            
            ByteArray output = new ByteArray();
            GMime.StreamMem output_stream = new GMime.StreamMem.with_byte_array(output);
            output_stream.set_owner(false);
            
            // Convert the encoding and character set.
            GMime.StreamFilter filter = new GMime.StreamFilter(output_stream);
            if (encoding != null)
                filter.add(new GMime.FilterBasic(GMime.content_encoding_from_string(encoding), false));
            
            if (charset != null)
                filter.add(new GMime.FilterCharset(charset, "UTF8"));
            
            input_stream.write_to_stream(filter);
            uint8[] data = output.data;
            data += (uint8) '\0';
            buffer = new Geary.Memory.StringBuffer((string) data);
        }
        
        base (buffer);
    }
}

