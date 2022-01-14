/*
 * Copyright © 2016 Software Freedom Conservancy Inc.
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** A network connection to a SMTP service. */
internal class Geary.Smtp.ClientConnection : BaseObject, Logging.Source {


    public const uint DEFAULT_TIMEOUT_SEC = 20;


    public Geary.Smtp.Capabilities? capabilities { get; private set; default = null; }

    /** {@inheritDoc} */
    public override string logging_domain {
        get { return ClientService.PROTOCOL_LOGGING_DOMAIN; }
    }

    /** {@inheritDoc} */
    public Logging.Source? logging_parent { get { return _logging_parent; } }
    private weak Logging.Source? _logging_parent = null;

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
            debug("Already connected");
            return null;
        }

        cx = socket_cx = yield endpoint.connect_async(cancellable);
        set_data_streams(cx);

        // read and deserialize the greeting
        Greeting greeting = new Greeting(yield recv_response_lines_async(cancellable));
        debug("SMTP Greeting: %s", greeting.to_string());

        return greeting;
    }

    public async bool disconnect_async(Cancellable? cancellable = null) throws Error {
        if (cx == null)
            return false;

        Error? disconnect_error = null;
        try {
            yield cx.close_async(Priority.DEFAULT, cancellable);
        } catch (Error err) {
            disconnect_error = err;
        }

        cx = null;

        if (disconnect_error != null)
            throw disconnect_error;

        return true;
    }

    /**
     * Returns the final Response of the challenge-response.
     */
    public async Response authenticate_async(Authenticator authenticator, Cancellable? cancellable = null)
        throws Error {
        check_connected();

        Response response = yield transaction_async(authenticator.initiate(), cancellable);

        debug("Initiated SMTP %s authentication", authenticator.to_string());

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

            debug("SMTP AUTH Challenge recvd");

            yield Stream.write_all_async(douts, data, cancellable);
            douts.put_string(DataFormat.LINE_TERMINATOR);
            yield douts.flush_async(Priority.DEFAULT, cancellable);

            response = yield recv_response_async(cancellable);
        }

        return response;
    }

    /**
     * Sends a block of data
     *
     * This first issues a DATA command and transmits the block if the
     * appropriate response is sent.
     *
     * Returns the final Response of the transaction. If the
     * ResponseCode is not a successful completion, the message should
     * not be considered sent.
     */
    public async Response send_data_async(Memory.Buffer data,
                                          GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        check_connected();

        // In the case of DATA, want to receive an intermediate response code, specifically 354
        Response response = yield transaction_async(new Request(Command.DATA), cancellable);
        if (response.code.is_start_data()) {
            debug("SMTP Data: <%z>", data.size);

            // ready to go, send and commit
            yield Stream.write_all_async(this.douts, data, cancellable);

            // terminate buffer and flush to server
            yield Stream.write_string_async(
                this.douts, DataFormat.DATA_TERMINATOR, cancellable
            );
            yield this.douts.flush_async(Priority.DEFAULT, cancellable);

            response = yield recv_response_async(cancellable);
        }
        return response;
    }

    public async void send_request_async(Request request, Cancellable? cancellable = null) throws Error {
        check_connected();

        debug("SMTP Request: %s", request.to_string());

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
        debug("SMTP Response: %s", response.to_string());
        return response;
    }

    /**
     * Sends the appropriate HELO/EHLO command and returns the response of the one that worked.
     * Also saves the server's capabilities in the capabilities property (overwriting any that may
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
                debug("Unable to lookup local address for %s: %s",
                      local_addr.to_string(), err.message);
            }
        }

        if (!String.is_empty(fqdn) && !("." in fqdn)) {
            debug("Ignoring hostname, because it is not a FQDN: %s", fqdn);
            fqdn = null;
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
        if (endpoint.tls_method == TlsNegotiationMethod.START_TLS) {
            if (!capabilities.has_capability(Capabilities.STARTTLS)) {
                throw new SmtpError.NOT_SUPPORTED(
                    "STARTTLS not available for %s", endpoint.to_string()
                );
            }

            Response starttls_response = yield transaction_async(new Request(Command.STARTTLS));
            if (!starttls_response.code.is_starttls_ready())
                throw new SmtpError.STARTTLS_FAILED("STARTTLS failed: %s", response.to_string());

            TlsClientConnection tls_cx = yield endpoint.starttls_handshake_async(cx, cancellable);
            cx = tls_cx;
            set_data_streams(tls_cx);

            // Now that we are on an encrypted line we need to say hello again in order to get the
            // updated capabilities.
            response = yield say_hello_async(cancellable);
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

    /** {@inheritDoc} */
    public virtual Logging.State to_logging_state() {
        return new Logging.State(
            this,
            "%s/%s",
            endpoint.to_string(),
            is_connected() ? "connected" : "disconnected"
        );
    }

    /** Sets the service's logging parent. */
    internal void set_logging_parent(Logging.Source parent) {
        this._logging_parent = parent;
    }

    private void set_data_streams(IOStream stream) {
        dins = new DataInputStream(stream.input_stream);
        dins.set_newline_type(DataFormat.LINE_TERMINATOR_TYPE);
        dins.set_close_base_stream(false);
        douts = new DataOutputStream(stream.output_stream);
        douts.set_close_base_stream(false);
    }
}
