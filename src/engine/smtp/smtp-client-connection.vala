/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Smtp.ClientConnection {
    public const uint16 DEFAULT_PORT = 25;
    public const uint16 DEFAULT_PORT_SSL = 465;
    public const uint16 DEFAULT_PORT_STARTTLS = 587;
    
    public const uint DEFAULT_TIMEOUT_SEC = 60;
    
    public Geary.Smtp.Capabilities? capabilities { get; private set; default = null; }
    
    private Geary.Endpoint endpoint;
    private IOStream? cx = null;
    private SocketConnection? socket_cx = null;
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
        
        cx = socket_cx = yield endpoint.connect_async(cancellable);
        set_data_streams(cx);
        
        // read and deserialize the greeting
        Greeting greeting = new Greeting(yield recv_response_lines_async(cancellable));
        Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP Greeting: %s", to_string(), greeting.to_string());
        
        return greeting;
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
        
        switch (endpoint.attempt_starttls(capabilities.has_capability(Capabilities.STARTTLS))) {
            case Endpoint.AttemptStarttls.YES:
                Response response = yield transaction_async(new Request(Command.STARTTLS));
                if (!response.code.is_starttls_ready()) {
                    throw new SmtpError.STARTTLS_FAILED("STARTTLS failed: %s", response.to_string());
                }
                
                // TLS started, lets wrap the connection and shake hands.
                TlsClientConnection tls_cx = TlsClientConnection.new(cx, socket_cx.get_remote_address());
                cx = tls_cx;
                tls_cx.set_validation_flags(TlsCertificateFlags.UNKNOWN_CA);
                set_data_streams(tls_cx);
                yield tls_cx.handshake_async(Priority.DEFAULT, cancellable);
                
                // Now that we are on an encrypted line we need to say hello again in order to get the
                // updated capabilities.
                yield say_hello_async(cancellable);
            break;
            
            case Endpoint.AttemptStarttls.NO:
                // do nothing
            break;
            
            case Endpoint.AttemptStarttls.HALT:
            default:
                throw new SmtpError.NOT_SUPPORTED("STARTTLS not available for %s", endpoint.to_string());
        }
        
        Response response = yield transaction_async(authenticator.initiate(), cancellable);
        
        Logging.debug(Logging.Flag.NETWORK, "[%s] Initiated SMTP %s authentication", to_string(),
            authenticator.to_string());
        
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
            
            Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP AUTH Challenge: %s <%ldb>", to_string(),
                Geary.String.uint8_to_string(data), data.length);
            
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
        
        Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP Data: <%ldb>", to_string(), data.length);
        
        yield Stream.write_all_async(douts, data, 0, -1, Priority.DEFAULT, cancellable);
        douts.put_string(DataFormat.DATA_TERMINATOR);
        yield douts.flush_async(Priority.DEFAULT, cancellable);
        
        return yield recv_response_async(cancellable);
    }
    
    public async void send_request_async(Request request, Cancellable? cancellable = null) throws Error {
        check_connected();
        
        Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP Request: %s", to_string(), request.to_string());
        
        douts.put_string(request.serialize());
        douts.put_string(DataFormat.LINE_TERMINATOR);
        yield douts.flush_async(Priority.DEFAULT, cancellable);
    }
    
    private async Gee.List<ResponseLine> recv_response_lines_async(Cancellable? cancellable) throws Error {
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
        
        return lines;
    }
    
    public async Response recv_response_async(Cancellable? cancellable = null) throws Error {
        Response response = new Response(yield recv_response_lines_async(cancellable));
        
        Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP Response: %s", to_string(), response.to_string());
        
        return response;
    }

    public async Response say_hello_async(Cancellable? cancellable = null) throws Error {
        check_connected();
        
        // get local address as FQDN to greet server ... note that this merely returns the DHCP address
        // for machines behind a NAT
        InetAddress local_addr = ((InetSocketAddress) socket_cx.get_local_address()).get_address();
        
        // only attempt to produce a FQDN if not a local address and use the local address if
        // unavailable
        string? fqdn = null;
        if (!local_addr.is_link_local && !local_addr.is_loopback && !local_addr.is_site_local) {
            try {
                fqdn = yield Resolver.get_default().lookup_by_address_async(local_addr, cancellable);
            } catch (Error err) {
                debug("[%s] Unable to lookup local address for %s: %s", to_string(),
                    local_addr.to_string(), err.message);
            }
        }
        
        // try EHLO first, then fall back on HELO
        EhloRequest ehlo = !String.is_empty(fqdn) ? new EhloRequest(fqdn) : new EhloRequest.for_local_address(local_addr);
        Response response = yield transaction_async(ehlo, cancellable);
        if (response.code.is_success_completed()) {
            // save list of caps returned in EHLO command, skipping first line because it's the 
            // EHLO response
            capabilities = new Geary.Smtp.Capabilities();
            capabilities.add_ehlo_response(response);
        } else {
            string first_response = response.to_string().strip();
            HeloRequest helo = !String.is_empty(fqdn) ? new HeloRequest(fqdn) : new HeloRequest.for_local_address(local_addr);
            response = yield transaction_async(helo, cancellable);
            if (!response.code.is_success_completed()) {
                throw new SmtpError.SERVER_ERROR("Refused service: \"%s\" and \"%s\"", first_response,
                    response.to_string().strip());
            }
        }
        
        return response;
    }

    public async Response quit_async(Cancellable? cancellable = null) throws Error {
        capabilities = null;
        return yield transaction_async(new Request(Command.QUIT), cancellable);
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

    private void set_data_streams(IOStream stream) {
        dins = new DataInputStream(stream.input_stream);
        dins.set_newline_type(DataFormat.LINE_TERMINATOR_TYPE);
        dins.set_close_base_stream(false);
        douts = new DataOutputStream(stream.output_stream);
        douts.set_close_base_stream(false);
    }
}

