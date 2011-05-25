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

public class Geary.RFC822.Date : Geary.Common.StringMessageData, Geary.RFC822.MessageData {
    public Date(string value) {
        base (value);
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
    private Gee.List<MailboxAddress> addrs = new Gee.ArrayList<MailboxAddress>();
    
    public MailboxAddresses(Gee.Collection<MailboxAddress> addrs) {
        this.addrs.add_all(addrs);
    }
    
    public int get_count() {
        return addrs.size;
    }
    
    public MailboxAddress? get_at(int index) {
        return addrs.get(index);
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

