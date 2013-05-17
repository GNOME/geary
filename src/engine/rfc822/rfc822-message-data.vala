/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * RFC822.MessageData represents a base class for all the various elements that may be present in
 * an RFC822 message header.  Note that some common elements (such as MailAccount) are not
 * MessageData because they exist in an RFC822 header in list (i.e. multiple email addresses) form.
 */

public interface Geary.RFC822.MessageData : Geary.MessageData.AbstractMessageData {
}

public class Geary.RFC822.MessageID : Geary.MessageData.StringMessageData, Geary.RFC822.MessageData {
    public MessageID(string value) {
        base (value);
    }
}

/**
 * A Message-ID list stores its IDs from earliest to latest.
 */
public class Geary.RFC822.MessageIDList : Geary.MessageData.AbstractMessageData, Geary.RFC822.MessageData {
    public Gee.List<MessageID> list { get; private set; }
    
    public MessageIDList() {
        list = new Gee.ArrayList<MessageID>();
    }
    
    public MessageIDList.from_list(Gee.List<MessageID> list) {
        this ();
        
        foreach(MessageID msg_id in list)
            this.list.add(msg_id);
    }
    
    public MessageIDList.single(MessageID msg_id) {
        this ();
        
        list.add(msg_id);
    }
    
    public MessageIDList.from_rfc822_string(string value) {
        this ();
        
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
            
            list.add(new MessageID(valid));
        }
    }
    
    public override string to_string() {
        return "MessageIDList (%d)".printf(list.size);
    }
    
    public virtual string to_rfc822_string() {
        string[] strings = new string[list.size];
        for(int i = 0; i < list.size; ++i)
            strings[i] = list[i].value;
        
        return string.joinv(" ", strings);
    }
}

public class Geary.RFC822.Date : Geary.RFC822.MessageData, Geary.MessageData.AbstractMessageData,
    Gee.Hashable<Geary.RFC822.Date> {
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
    
    public virtual bool equal_to(Geary.RFC822.Date other) {
        if (this == other)
            return true;
        
        return value.equal(other.value);
    }
    
    public virtual uint hash() {
        return value.hash();
    }
    
    public override string to_string() {
        return original;
    }
}

public class Geary.RFC822.Size : Geary.MessageData.LongMessageData, Geary.RFC822.MessageData {
    public Size(long value) {
        base (value);
    }
}

public class Geary.RFC822.Subject : Geary.MessageData.StringMessageData,
    Geary.MessageData.SearchableMessageData, Geary.RFC822.MessageData {
    public const string REPLY_PREFACE = "Re:";
    public const string FORWARD_PREFACE = "Fwd:";
    
    public string original { get; private set; }
    
    public Subject(string value) {
        base (value);
        original = value;
    }
    
    public Subject.decode(string value) {
        base (GMime.utils_header_decode_text(value));
        original = value;
    }
    
    public bool is_reply() {
        return value.down().has_prefix(REPLY_PREFACE.down());
    }
    
    public Subject create_reply() {
        return is_reply() ? new Subject(value) : new Subject("%s %s".printf(REPLY_PREFACE,
            value));
    }
    
    public bool is_forward() {
        return value.down().has_prefix(FORWARD_PREFACE.down());
    }
    
    public Subject create_forward() {
        return is_forward() ? new Subject(value) : new Subject("%s %s".printf(FORWARD_PREFACE,
            value));
    }
    
    /**
     * See Geary.MessageData.SearchableMessageData.
     */
    public string to_searchable_string() {
        return value;
    }
}

public class Geary.RFC822.Header : Geary.MessageData.BlockMessageData, Geary.RFC822.MessageData {
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

public class Geary.RFC822.Text : Geary.MessageData.BlockMessageData, Geary.RFC822.MessageData {
    public Text(Geary.Memory.AbstractBuffer buffer) {
        base ("RFC822.Text", buffer);
    }
}

public class Geary.RFC822.Full : Geary.MessageData.BlockMessageData, Geary.RFC822.MessageData {
    public Full(Geary.Memory.AbstractBuffer buffer) {
        base ("RFC822.Full", buffer);
    }
}

// Used for decoding preview text.
public class Geary.RFC822.PreviewText : Geary.RFC822.Text {
    public PreviewText(Geary.Memory.AbstractBuffer _buffer) {
        base (_buffer);
    }
    
    public PreviewText.with_header(Geary.Memory.AbstractBuffer buffer, Geary.Memory.AbstractBuffer
        preview_header) {
        string? charset = null;
        string? encoding = null;
        bool is_html = false;
        
        // Parse the header.
        GMime.Stream header_stream = new GMime.StreamMem.with_buffer(
            preview_header.get_array());
        GMime.Parser parser = new GMime.Parser.with_stream(header_stream);
        GMime.Part? part = parser.construct_part() as GMime.Part;
        if (part != null) {
            is_html = (part.get_content_type().to_string() == "text/html");
            
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
        
        if (!String.is_empty(charset))
            filter.add(Geary.RFC822.Utils.create_utf8_filter_charset(charset));
        
        input_stream.write_to_stream(filter);
        uint8[] data = output.data;
        data += (uint8) '\0';
        
        // Fix the preview up by removing HTML tags, redundant white space, common types of
        // message armor, text-based quotes, and various MIME fields.
        string preview_text = "";
        string original_text = is_html ? Geary.HTML.remove_html_tags((string) data) : (string) data;
        string[] all_lines = original_text.split("\r\n");
        bool in_header = false; // True after a header
        
        foreach(string line in all_lines) {
            if (in_header && line.has_prefix(" ") || line.has_prefix("\t")) {
                continue; // Skip "folded" (multi-line) headers.
            } else {
                in_header = false;
            }
            
            if (line.has_prefix("Content-")) {
                in_header = true;
                continue;
            }
            
            if (Geary.String.is_empty_or_whitespace(line))
                continue;
            
            if (line.has_prefix("--"))
                continue;
            
            if (line.has_prefix(">"))
                continue;
            
            preview_text += " " + line;
        }
        
        base (new Geary.Memory.StringBuffer(Geary.String.reduce_whitespace(preview_text)));
    }
    
    public PreviewText.from_string(string preview) {
        base (new Geary.Memory.StringBuffer(preview));
    }
}

