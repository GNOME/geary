/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ClientSession : Object, Geary.Account {
    // Need this because delegates with targets cannot be stored in ADTs.
    private class CommandCallback {
        public SourceFunc callback;
        
        public CommandCallback(SourceFunc callback) {
            this.callback = callback;
        }
    }
    
    private string server;
    private uint default_port;
    private ClientConnection? cx = null;
    private Mailbox? current_mailbox = null;
    private Gee.Queue<CommandCallback> cb_queue = new Gee.LinkedList<CommandCallback>();
    private Gee.Queue<CommandResponse> cmd_response_queue = new Gee.LinkedList<CommandResponse>();
    private CommandResponse current_cmd_response = new CommandResponse();
    private bool awaiting_connect_response = false;
    private ServerData? connect_response = null;
    
    public ClientSession(string server, uint default_port) {
        this.server = server;
        this.default_port = default_port;
    }
    
    public Tag? generate_tag() {
        return (cx != null) ? cx.generate_tag() : null;
    }
    
    public async void connect_async(string user, string pass, Cancellable? cancellable = null)
        throws Error {
        if (cx != null)
            return;
        
        cx = new ClientConnection(server, ClientConnection.DEFAULT_PORT_TLS);
        cx.connected.connect(on_connected);
        cx.disconnected.connect(on_disconnected);
        cx.sent_command.connect(on_sent_command);
        cx.received_status_response.connect(on_received_status_response);
        cx.received_server_data.connect(on_received_server_data);
        cx.received_bad_response.connect(on_received_bad_response);
        cx.receive_failure.connect(on_receive_failed);
        
        yield cx.connect_async(cancellable);
        
        // wait for the initial OK response from the server
        cb_queue.offer(new CommandCallback(connect_async.callback));
        awaiting_connect_response = true;
        yield;
        
        assert(connect_response != null);
        Status status = Status.from_parameter(
            (StringParameter) connect_response.get_as(1, typeof(StringParameter)));
        if (status != Status.OK)
            throw new ImapError.SERVER_ERROR("Unable to connect: %s", connect_response.to_string());
        
        // issue login command
        yield send_command_async(new LoginCommand(cx.generate_tag(), user, pass), cancellable);
    }
    
    public async void disconnect_async(string user, string pass, Cancellable? cancellable = null)
        throws Error {
        if (cx == null)
            return;
        
        CommandResponse response = yield send_command_async(new LogoutCommand(cx.generate_tag()),
            cancellable);
        if (response.status_response.status != Status.OK)
            message("Logout to %s failed: %s", server, response.status_response.to_string());
        
        yield cx.disconnect_async(cancellable);
        
        cx = null;
    }
    
    public async CommandResponse send_command_async(Command cmd, Cancellable? cancellable = null) 
        throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", server);
        
        yield cx.send_async(cmd, Priority.DEFAULT, cancellable);
        
        cb_queue.offer(new CommandCallback(send_command_async.callback));
        yield;
        
        CommandResponse? cmd_response = cmd_response_queue.poll();
        assert(cmd_response != null);
        assert(cmd_response.is_sealed());
        assert(cmd_response.status_response.tag.equals(cmd.tag));
        
        return cmd_response;
    }
    
    public async Geary.Folder open(string name, Cancellable? cancellable = null) throws Error {
        if (cx == null)
            throw new ImapError.NOT_CONNECTED("Not connected to %s", server);
        
        assert(current_mailbox == null);
        
        yield send_command_async(new ExamineCommand(cx.generate_tag(), name), cancellable);
        current_mailbox = new Mailbox(name, this);
        
        return current_mailbox;
    }
    
    private void on_connected() {
        debug("Connected to %s", server);
    }
    
    private void on_disconnected() {
        debug("Disconnected from %s", server);
    }
    
    private void on_sent_command(Command cmd) {
        debug("Sent command %s", cmd.to_string());
    }
    
    private void on_received_status_response(StatusResponse status_response) {
        assert(!current_cmd_response.is_sealed());
        current_cmd_response.seal(status_response);
        assert(current_cmd_response.is_sealed());
        
        cmd_response_queue.offer(current_cmd_response);
        current_cmd_response = new CommandResponse();
        
        CommandCallback? cmd_callback = cb_queue.poll();
        assert(cmd_callback != null);
        
        Idle.add(cmd_callback.callback);
    }
    
    private void on_received_server_data(ServerData server_data) {
        // The first response from the server is an untagged status response, which is considered
        // ServerData in our model.  This captures that and treats it as such.
        if (awaiting_connect_response) {
            awaiting_connect_response = false;
            connect_response = server_data;
            
            CommandCallback? cmd_callback = cb_queue.poll();
            assert(cmd_callback != null);
            
            Idle.add(cmd_callback.callback);
            
            return;
        }
        
        current_cmd_response.add_server_data(server_data);
    }
    
    private void on_received_bad_response(RootParameters root, ImapError err) {
        debug("Received bad response %s: %s", root.to_string(), err.message);
    }
    
    private void on_receive_failed(Error err) {
        debug("Receive failed: %s", err.message);
    }
}

