/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Object, Geary.Folder {
    public string name { get; private set; }
    
    private ClientSession sess;
    
    internal Mailbox(string name, ClientSession sess) {
        this.name = name;
        this.sess = sess;
    }
    
    public MessageStream? read(int low, int count) {
        return new MessageStreamImpl(sess, low, count);
    }
}

private class Geary.Imap.MessageStreamImpl : Object, Geary.MessageStream {
    private ClientSession sess;
    private string span;
    
    public MessageStreamImpl(ClientSession sess, int low, int count) {
        assert(count > 0);
        
        this.sess = sess;
        span = (count > 1) ? "%d:%d".printf(low, low + count - 1) : "%d".printf(low);
    }
    
    public async Gee.List<Message>? read(Cancellable? cancellable = null) throws Error {
        CommandResponse resp = yield sess.send_command_async(new FetchCommand(sess.generate_tag(),
            span, { FetchDataItem.ENVELOPE }), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR(resp.status_response.text);
        
        Gee.List<Message> msgs = new Gee.ArrayList<Message>();
        foreach (ServerData data in resp.server_data) {
            StringParameter? label = data.get(2) as StringParameter;
            if (label == null || label.value.down() != "fetch") {
                debug("Not fetch data: %s", (label == null) ? "(null)" : label.value);
                continue;
            }
            
            StringParameter msg_num = (StringParameter) data.get_as(1, typeof(StringParameter));
            ListParameter envelope = (ListParameter) data.get_as(3, typeof(ListParameter));
            
            ListParameter fields = (ListParameter) envelope.get_as(1, typeof(ListParameter));
            
            StringParameter date = (StringParameter) fields.get_as(0, typeof(StringParameter));
            StringParameter subject = (StringParameter) fields.get_as(1, typeof(StringParameter));
            
            ListParameter from_fields = (ListParameter) fields.get_as(3, typeof(ListParameter));
            ListParameter first_from = (ListParameter) from_fields.get_as(0, typeof(ListParameter));
            StringParameter from_name = (StringParameter) first_from.get_as(0, typeof(StringParameter));
            StringParameter from_mailbox = (StringParameter) first_from.get_as(2, typeof(StringParameter));
            StringParameter from_domain = (StringParameter) first_from.get_as(3, typeof(StringParameter));
            
            Message msg = new Message(int.parse(msg_num.value),
                "%s <%s@%s>".printf(from_name.value, from_mailbox.value, from_domain.value),
                subject.value, date.value);
            msgs.add(msg);
        }
        
        return msgs;
    }
}

