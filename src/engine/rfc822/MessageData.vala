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

public class Geary.RFC822.Date : Geary.RFC822.MessageData, Geary.Common.MessageData {
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
    public Subject(string value) {
        base (value);
    }
}

public class Geary.RFC822.MailboxAddresses : Geary.Common.MessageData, Geary.RFC822.MessageData {
    public int size { get { return addrs.size; } }
    
    private Gee.List<MailboxAddress> addrs = new Gee.ArrayList<MailboxAddress>();
    
    public MailboxAddresses(Gee.Collection<MailboxAddress> addrs) {
        this.addrs.add_all(addrs);
    }
    
    public MailboxAddress? get(int index) {
        return addrs.get(index);
    }
    
    public Gee.Iterator<MailboxAddress> iterator() {
        return addrs.iterator();
    }
    
    public Gee.List<MailboxAddress> get_all() {
        return addrs.read_only_view;
    }
    
    public override string to_string() {
        switch (addrs.size) {
            case 0:
                return "(no addresses)";
            
            case 1:
                return addrs[0].to_string();
            
            default:
                StringBuilder builder = new StringBuilder();
                foreach (MailboxAddress addr in addrs) {
                    if (!String.is_empty(builder.str))
                        builder.append(", ");
                    
                    builder.append(addr.to_string());
                }
                
                return builder.str;
        }
    }
}

public class Geary.RFC822.Header : Geary.Common.BlockMessageData, Geary.RFC822.MessageData {
    public Header(Geary.Memory.AbstractBuffer buffer) {
        base ("RFC822.Header", buffer);
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

