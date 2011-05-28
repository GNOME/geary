/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Mailbox : Object, Geary.Folder {
    public string name { get; private set; }
    
    private ClientSession sess;
    private bool is_closed = false;
    
    internal Mailbox(string name, ClientSession sess) {
        this.name = name;
        this.sess = sess;
    }
    
    ~Mailbox() {
        assert(is_closed);
    }
    
    public MessageStream? read(int low, int count) {
        return new MessageStreamImpl(sess, low, count);
    }
    
    public async void close(Cancellable? cancellable = null) throws Error {
        yield sess.close_mailbox_async(cancellable);
        is_closed = true;
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
            span, { FetchDataType.ENVELOPE }), cancellable);
        
        if (resp.status_response.status != Status.OK)
            throw new ImapError.SERVER_ERROR("Server error: %s", resp.to_string());
        
        Gee.List<Message> msgs = new Gee.ArrayList<Message>();
        
        FetchResults[] results = FetchResults.decode(resp);
        foreach (FetchResults res in results) {
            Envelope envelope = (Envelope) res.get_data(FetchDataType.ENVELOPE);
            msgs.add(new Message(res.msg_num, envelope.from, envelope.subject, envelope.sent));
        }
        
        return msgs;
    }
}

