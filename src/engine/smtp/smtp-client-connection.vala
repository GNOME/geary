/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Smtp.ClientConnection {
    public const uint16 DEFAULT_PORT = 25;
    public const uint16 SUBMISSION_PORT = 587;
    public const uint16 SECURE_SMTP_PORT = 465;
    
    private Geary.Endpoint endpoint;
    private SocketConnection? cx = null;
    private DataInputStream? dins = null;
    private DataOutputStream douts = null;
    
    public ClientConnection(Geary.Endpoint endpoint) {
        this.endpoint = endpoint;
    }
    
    public bool is_connected() {
        return (cx != null);
    }
    
    public async Greeting? connect_async(Cancellable? cancellable = null) throws Error {
        if (cx != null) {
            debug("Already connected to %s", to_string());
            
            return null;
        }
        
        cx = yield endpoint.connect_async(cancellable);
        
        dins = new DataInputStream(cx.input_stream);
        dins.set_newline_type(DataFormat.LINE_TERMINATOR_TYPE);
        douts = new DataOutputStream(cx.output_stream);
        
        // read and deserialize the greeting
        return Greeting.deserialize(yield read_line_async(cancellable));
    }
    
    public async bool disconnect_async(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            return false;
        
        yield cx.close_async(Priority.DEFAULT, cancellable);
        cx = null;
        
        return true;
    }
    
    /**
     * Returns the final Response of the challenge-response.
     */
    public async Response authenticate_async(Authenticator authenticator, Cancellable? cancellable = null)
        throws Error {
        check_connected();
        
        Response response = yield transaction_async(authenticator.initiate(), cancellable);
        
        // Possible for initiate() Request to:
        // (a) immediately generate success (due to valid authentication being passed in Request);
        // (b) immediately fails;
        // or (c) result in response asking for more.
        //
        // Only (c) keeps the challenge-response alive.  Other possibilities means the process has
        // completed.
        int step = 0;
        while (response.code.is_success_intermediate()) {
            uint8[]? data = authenticator.challenge(step++, response);
            if (data == null || data.length == 0)
                data = DataFormat.CANCEL_AUTHENTICATION.data;
            
            yield Stream.write_all_async(douts, data, 0, -1, Priority.DEFAULT, cancellable);
            douts.put_string(DataFormat.LINE_TERMINATOR);
            yield douts.flush_async(Priority.DEFAULT, cancellable);
            
            response = yield recv_response_async(cancellable);
        }
        
        return response;
    }
    
    /**
     * Sends a block of data (mail message) by first issuing the DATA command and transmitting
     * the block if the appropriate response is sent.  The data block should *not* have the SMTP
     * data terminator (<CR><LF><dot><CR><LF>).  The caller is also responsible to ensure that this
     * pattern does not occur anywhere in the data, causing an early termination of the message.
     *
     * Returns the final Response of the transaction.  If the ResponseCode is not a successful
     * completion, the message should not be considered sent.
     */
    public async Response send_data_async(uint8[] data, Cancellable? cancellable = null) throws Error {
        check_connected();
        
        // In the case of DATA, want to receive an intermediate response code, specifically 354
        Response response = yield transaction_async(new Request(Command.DATA), cancellable);
        if (!response.code.is_start_data())
            return response;
        
        yield Stream.write_all_async(douts, data, 0, -1, Priority.DEFAULT, cancellable);
        douts.put_string(DataFormat.DATA_TERMINATOR);
        yield douts.flush_async(Priority.DEFAULT, cancellable);
        
        return yield recv_response_async(cancellable);
    }
    
    public async void send_request_async(Request request, Cancellable? cancellable = null) throws Error {
        check_connected();
        
        douts.put_string(request.serialize());
        douts.put_string(DataFormat.LINE_TERMINATOR);
        yield douts.flush_async(Priority.DEFAULT, cancellable);
    }
    
    public async Response recv_response_async(Cancellable? cancellable = null) throws Error {
        check_connected();
        
        Gee.List<ResponseLine> lines = new Gee.ArrayList<ResponseLine>();
        for (;;) {
            ResponseLine line = ResponseLine.deserialize(yield read_line_async(cancellable));
            lines.add(line);
            
            if (!line.continued)
                break;
        }
        
        // lines should never be empty; if it is, then somebody didn't throw an exception
        assert(lines.size > 0);
        
        return new Response(lines);
    }
    
    public async Response transaction_async(Request request, Cancellable? cancellable = null)
        throws Error {
        yield send_request_async(request, cancellable);
        
        return yield recv_response_async(cancellable);
    }
    
    private async string read_line_async(Cancellable? cancellable) throws Error {
        size_t length;
        string? line = yield dins.read_line_async(Priority.DEFAULT, cancellable, out length);
        
        if (String.is_empty(line))
            throw new IOError.CLOSED("End of stream detected on %s", to_string());
        
        return line;
    }
    
    private void check_connected() throws Error {
        if (cx == null)
            throw new SmtpError.NOT_CONNECTED("Not connected to %s", to_string());
    }
    
    public string to_string() {
        return endpoint.to_string();
    }
}

