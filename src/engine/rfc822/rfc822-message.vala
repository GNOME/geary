/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.RFC822.Message : Object {
    public GMime.Message? message { get; private set; }
    
    public Message(Full full) {
        GMime.Parser parser = new GMime.Parser.with_stream(
            new GMime.StreamMem.with_buffer(full.buffer.get_buffer()));
        
        message = parser.construct_message();
    }
    
    public Message.from_parts(Header header, Text body) {
        GMime.StreamCat stream_cat = new GMime.StreamCat();
        stream_cat.add_source(new GMime.StreamMem.with_buffer(header.buffer.get_buffer()));
        stream_cat.add_source(new GMime.StreamMem.with_buffer(body.buffer.get_buffer()));
        
        GMime.Parser parser = new GMime.Parser.with_stream(stream_cat);
        
        message = parser.construct_message();
    }
    
    public Message.from_composed_email(Geary.ComposedEmail email) {
        message = new GMime.Message(true);
        
        // Required headers
        message.set_sender(email.from);
        message.set_date((time_t) email.date.to_unix(),
            (int) (email.date.get_utc_offset() / TimeSpan.HOUR));
        
        // Optional headers
        if (!String.is_empty(email.to))
            message.add_recipient(GMime.RecipientType.TO, "", email.to);
        
        if (!String.is_empty(email.cc))
            message.add_recipient(GMime.RecipientType.CC, "", email.cc);
        
        if (!String.is_empty(email.bcc))
            message.add_recipient(GMime.RecipientType.BCC, "", email.bcc);
        
        if (!String.is_empty(email.subject))
            message.set_subject(email.subject);
        
        // Body (also optional)
        if (!String.is_empty(email.body)) {
            GMime.DataWrapper content = new GMime.DataWrapper.with_stream(
                new GMime.StreamMem.with_buffer(email.body.data),
                GMime.ContentEncoding.DEFAULT);
            
            GMime.Part part = new GMime.Part();
            part.set_content_object(content);
            
            message.set_mime_part(part);
        }
    }
    
    public bool is_decoded() {
        return message != null;
    }
    
    public Geary.Memory.AbstractBuffer get_first_mime_part_of_content_type(string content_type)
        throws RFC822.Error {
        if (!is_decoded())
            throw new RFC822.Error.INVALID("Message could not be decoded");
        
        // search for content type starting from the root
        GMime.Part? part = find_first_mime_part(message.get_mime_part(), content_type);
        if (part == null) {
            throw new RFC822.Error.NOT_FOUND("Could not find a MIME part with content-type %s",
                content_type);
        }
        
        // convert payload to a buffer
        GMime.DataWrapper? wrapper = part.get_content_object();
        if (wrapper == null) {
            throw new RFC822.Error.INVALID("Could not get the content wrapper for content-type %s",
                content_type);
        }
        
        ByteArray byte_array = new ByteArray();
        GMime.StreamMem stream = new GMime.StreamMem.with_byte_array(byte_array);
        stream.set_owner(false);
        
        wrapper.write_to_stream(stream);
        
        return new Geary.Memory.Buffer(byte_array.data, byte_array.len);
    }
    
    private GMime.Part? find_first_mime_part(GMime.Object current_root, string content_type) {
        // descend looking for the content type in a GMime.Part
        GMime.Multipart? multipart = current_root as GMime.Multipart;
        if (multipart != null) {
            int count = multipart.get_count();
            for (int ctr = 0; ctr < count; ctr++) {
                GMime.Part? child_part = find_first_mime_part(multipart.get_part(ctr), content_type);
                if (child_part != null)
                    return child_part;
            }
        }
        
        GMime.Part? part = current_root as GMime.Part;
        if (part != null && part.get_content_type().to_string() == content_type)
            return part;
        
        return null;
    }
}

