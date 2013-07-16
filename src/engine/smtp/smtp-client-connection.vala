/* Copyright 2011-2013 Yorba Foundation
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
            Memory.Buffer? data = authenticator.challenge(step++, response);
            if (data == null || data.size == 0)
                data = new Memory.StringBuffer(DataFormat.CANCEL_AUTHENTICATION);
            
            Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP AUTH Challenge recvd", to_string());
            
            yield Stream.write_all_async(douts, data, cancellable);
            douts.put_string(DataFormat.LINE_TERMINATOR);
            yield douts.flush_async(Priority.DEFAULT, cancellable);
            
            response = yield recv_response_async(cancellable);
        }
        
        return response;
    }

    /**
     * Sends a block of data (mail message) by first issuing the DATA command and transmitting
     * the block if the appropriate response is sent.
     *
     * Dot-stuffing is performed on the data if !already_dotstuffed.  See
     * [[http://tools.ietf.org/html/rfc2821#section-4.5.2]]
     *
     * Returns the final Response of the transaction.  If the ResponseCode is not a successful
     * completion, the message should not be considered sent.
     */
    public async Response send_data_async(Memory.Buffer data, bool already_dotstuffed,
        Cancellable? cancellable = null) throws Error {
        check_connected();
        
        // In the case of DATA, want to receive an intermediate response code, specifically 354
        Response response = yield transaction_async(new Request(Command.DATA), cancellable);
        if (!response.code.is_start_data())
            return response;
        
        Logging.debug(Logging.Flag.NETWORK, "[%s] SMTP Data: <%ldb>", to_string(), data.size);
        
        if (!already_dotstuffed) {
            // By using DataStreamNewlineType.ANY, we're assured to get each line and convert to
            // a proper line terminator for SMTP
            DataInputStream dins = new DataInputStream(data.get_input_stream());
            dins.set_newline_type(DataStreamNewlineType.ANY);
            
            // Read each line and dot-stuff if necessary
            for (;;) {
                size_t length;
                string? line = yield dins.read_line_async(Priority.DEFAULT, cancellable, out length);
                if (line == null)
                    break;
                
                // stuffing
                if (line[0] == '.')
                    yield Stream.write_string_async(douts, ".", cancellable);
                
                yield Stream.write_string_async(douts, line, cancellable);
                yield Stream.write_string_async(douts, DataFormat.LINE_TERMINATOR, cancellable);
            }
        } else {
            // ready to go, send and commit
            yield Stream.write_all_async(douts, data, cancellable);
        }
        
        // terminate buffer and flush to server
        yield Stream.write_string_async(douts, DataFormat.DATA_TERMINATOR, cancellable);
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
    
    /**
     * Sends the appropriate HELO/EHLO command and returns the response of the one that worked.
     * Also saves the server's capabilities in the capabilties property (overwriting any that may
     * already be present).
     */
    public async Response say_hello_async(Cancellable? cancellable) throws Error {
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
            // save list of caps returned in EHLO command
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
    
    /**
     * Sends the appropriate hello command to the server (EHLO / HELO) and establishes whatever
     * additional connection features are available (STARTTLS, compression).  For general-purpose
     * use, this is the preferred method for establishing a session with a server, as it will do
     * whatever is necessary to ensure quality-of-service and security.
     *
     * Note that this does *not* connect to the server; connect_async() should be used before
     * calling this method.
     *
     * Returns the Response of the final hello command (there may be more than one).
     */
    public async Response establish_connection_async(Cancellable? cancellable = null) throws Error {
        check_connected();
        
        // issue first HELO/EHLO, which will generate a set of capabiltiies
        Smtp.Response response = yield say_hello_async(cancellable);
        
        // STARTTLS, if required
        switch (endpoint.attempt_starttls(capabilities.has_capability(Capabilities.STARTTLS))) {
            case Endpoint.AttemptStarttls.YES:
                Response starttls_response = yield transaction_async(new Request(Command.STARTTLS));
                if (!starttls_response.code.is_starttls_ready())
                    throw new SmtpError.STARTTLS_FAILED("STARTTLS failed: %s", response.to_string());
                
                TlsClientConnection tls_cx = yield endpoint.starttls_handshake_async(cx,
                    socket_cx.get_remote_address(), cancellable);
                cx = tls_cx;
                set_data_streams(tls_cx);
                
                // Now that we are on an encrypted line we need to say hello again in order to get the
                // updated capabilities.
                response = yield say_hello_async(cancellable);
            break;
            
            case Endpoint.AttemptStarttls.NO:
                // do nothing
            break;
            
            case Endpoint.AttemptStarttls.HALT:
            default:
                throw new SmtpError.NOT_SUPPORTED("STARTTLS not available for %s", endpoint.to_string());
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

