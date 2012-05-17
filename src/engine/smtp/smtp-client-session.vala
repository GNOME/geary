/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Smtp.ClientSession {
    private ClientConnection cx;
    private Gee.List<string>? capabilities = null;
    private bool rset_required = false;
    
    public virtual signal void connected(Greeting greeting) {
    }
    
    public virtual signal void authenticated(Authenticator authenticator) {
    }
    
    public virtual signal void disconnected() {
    }
    
    public ClientSession(Geary.Endpoint endpoint) {
        cx = new ClientConnection(endpoint);
    }
    
    protected virtual void notify_connected(Greeting greeting) {
        connected(greeting);
    }
    
    protected virtual void notify_authenticated(Authenticator authenticator) {
        authenticated(authenticator);
    }
    
    protected virtual void notify_disconnected() {
        disconnected();
    }
    
    public async Greeting? login_async(Credentials? creds, Cancellable? cancellable = null) throws Error {
        if (cx.is_connected())
            throw new SmtpError.ALREADY_CONNECTED("Connection to %s already exists", to_string());
        
        Greeting? greeting = yield cx.connect_async(cancellable);
        if (greeting == null)
            throw new SmtpError.ALREADY_CONNECTED("Connection to %s already exists", to_string());
        
        // try EHLO first, then fall back on HELO
        Response response = yield cx.transaction_async(new Request(Command.EHLO), cancellable);
        if (response.code.is_success_completed()) {
            // save list of caps returned in EHLO command, skipping first line because it's the 
            // EHLO response
            capabilities = new Gee.ArrayList<string>();
            for (int ctr = 1; ctr < response.lines.size; ctr++) {
                if (!String.is_empty(response.lines[ctr].explanation))
                    capabilities.add(response.lines[ctr].explanation);
            }
        } else {
            response = yield cx.transaction_async(new Request(Command.HELO), cancellable);
            if (!response.code.is_success_completed())
                throw new SmtpError.SERVER_ERROR("Refused service: %s", response.to_string());
        }
        
        notify_connected(greeting);
        
        // authenticate if credentials supplied (in almost every case they should be)
        // TODO: Select an authentication method based on AUTH capabilities line, falling back on
        // LOGIN or PLAIN if none match or are present
        if (creds != null) {
            Authenticator authenticator = new LoginAuthenticator(creds);
            response = yield cx.authenticate_async(authenticator, cancellable);
            if (!response.code.is_success_completed())
                throw new SmtpError.AUTHENTICATION_FAILED("Unable to authenticate with %s", to_string());
            
            notify_authenticated(authenticator);
        }
        
        return greeting;
    }
    
    public async Response? logout_async(Cancellable? cancellable = null) throws Error {
        Response? response = null;
        try {
            response = yield cx.transaction_async(new Request(Command.QUIT), cancellable);
        } catch (Error err) {
            // catch because although error occurred, still attempt to close the connection
            message("Unable to QUIT: %s", err.message);
        }
        
        try {
            if (yield cx.disconnect_async(cancellable))
                disconnected();
        } catch (Error err2) {
            // again, catch error but still shut down
            message("Unable to disconnect: %s", err2.message);
        }
        
        rset_required = false;
        capabilities = null;
        
        return response;
    }
    
    public async void send_email_async(Geary.RFC822.Message email, Cancellable? cancellable = null)
        throws Error {
        if (!cx.is_connected())
            throw new SmtpError.NOT_CONNECTED("Not connected to %s", to_string());
        
        // RSET if required
        if (rset_required) {
            Response rset_response = yield cx.transaction_async(new Request(Command.RSET), cancellable);
            if (!rset_response.code.is_success_completed())
                rset_response.throw_error("Unable to RSET");
            
            rset_required = false;
        }
        
        // MAIL
        if (email.sender == null)
            throw new SmtpError.REQUIRED_FIELD("No sender in message");
        
        MailRequest mail_request = new MailRequest(email.sender);
        Response response = yield cx.transaction_async(mail_request, cancellable);
        if (!response.code.is_success_completed())
            response.throw_error("\"%s\" failed".printf(mail_request.to_string()));
        
        // at this point in the session state machine, a RSET is required to start a new
        // transmission if this fails at any point
        rset_required = true;
        
        // RCPTs
        Gee.List<RFC822.MailboxAddress>? addrlist = email.get_recipients();
        if (addrlist == null || addrlist.size == 0)
            throw new SmtpError.REQUIRED_FIELD("No recipients in message");
        
        yield send_rcpts_async(addrlist, cancellable);
        
        // DATA
        Geary.RFC822.Message email_copy = new Geary.RFC822.Message.without_bcc(email);
        response = yield cx.send_data_async(email_copy.get_body_rfc822_buffer().get_array(), cancellable);
        if (!response.code.is_success_completed())
            response.throw_error("Unable to send message");

        // if message was transmitted successfully, the state machine resets automatically
        rset_required = false;
    }
    
    private async void send_rcpts_async(Gee.List<RFC822.MailboxAddress>? addrlist,
        Cancellable? cancellable) throws Error {
        if (addrlist == null)
            return;
        
        // TODO: Support mailbox groups
        foreach (RFC822.MailboxAddress mailbox in addrlist) {
            RcptRequest rcpt_request = new RcptRequest.plain(mailbox.address);
            Response response = yield cx.transaction_async(rcpt_request, cancellable);
            if (!response.code.is_success_completed())
                response.throw_error("\"%s\" failed".printf(rcpt_request.to_string()));
        }
    }
    
    public string to_string() {
        return cx.to_string();
    }
}

