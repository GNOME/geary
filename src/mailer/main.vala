/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

MainLoop? main_loop = null;
int ec = 0;
Geary.Endpoint? endpoint = null;
Geary.Credentials? credentials = null;
Geary.ComposedEmail? composed_email = null;

async void main_async() throws Error {
    Geary.Smtp.ClientSession session = new Geary.Smtp.ClientSession(endpoint);
    
    Geary.Smtp.Greeting? greeting = yield session.login_async(credentials);
    stdout.printf("%s\n", greeting.to_string());
    
    for (int ctr = 0; ctr < arg_count; ctr++) {
        string subj_msg = "#%d".printf(ctr + 1);
        composed_email.subject = subj_msg;
        composed_email.body_text = subj_msg;
        
        Geary.RFC822.Message msg = new Geary.RFC822.Message.from_composed_email(composed_email);
        stdout.printf("\n\n%s\n\n", msg.to_string());
        
        yield session.send_email_async(msg.sender, msg);
        
        stdout.printf("Sent email #%d\n", ctr);
    }
    
    Geary.Smtp.Response? logout = yield session.logout_async();
    stdout.printf("%s\n", logout.to_string());
}

void on_main_completed(Object? object, AsyncResult result) {
    try {
        main_async.end(result);
    } catch (Error err) {
        stderr.printf("%s\n", err.message);
        ec = 1;
    }
    
    if (main_loop != null)
        main_loop.quit();
}

string arg_hostname;
int arg_port = 25;
bool arg_debug = false;
bool arg_gmail = false;
bool arg_no_tls = false;
string arg_user;
string arg_pass;
string arg_from;
string arg_to;
int arg_count = 1;
const OptionEntry[] options = {
    { "debug",    0,    0,  OptionArg.NONE,     ref arg_debug,  "Output debugging information", null },
    { "host",   'h',    0,  OptionArg.STRING,   ref arg_hostname, "SMTP server host",   "<hostname-or-dotted-address>" },
    { "port",   'P',    0,  OptionArg.INT,      ref arg_port,   "SMTP server port",     "<port-number>" },
    { "gmail",  'G',    0,  OptionArg.NONE,     ref arg_gmail,  "Gmail SMTP (no-tls ignored)", null },
    { "no-tls", 'I',    0,  OptionArg.NONE,     ref arg_no_tls, "Do not use TLS (insecure)", null },
    { "user",   'u',    0,  OptionArg.STRING,   ref arg_user,   "SMTP server username", "<username>" },
    { "pass",   'p',    0,  OptionArg.STRING,   ref arg_pass,   "SMTP server password", "<password>" },
    { "from",   'f',    0,  OptionArg.STRING,   ref arg_from,   "From (sender)",        "<email>" },
    { "to",     't',    0,  OptionArg.STRING,   ref arg_to,     "To (recipient)",       "<email>" },
    { "count",  'c',    0,  OptionArg.INT,      ref arg_count,  "Number of emails to send", null },
    { null }
};

bool verify_required(string? arg, string name) {
    if (!Geary.String.is_empty(arg))
        return true;
    
    stdout.printf("%s required\n", name);
    
    return false;
}

int main(string[] args) {
    var context = new OptionContext("");
    context.set_help_enabled(true);
    context.add_main_entries(options, null);
    try {
        context.parse(ref args);
    } catch (Error err) {
        error ("Failed to parse command line: %s", err.message);
    }
    
    if (!arg_gmail && !verify_required(arg_hostname, "Hostname"))
        return 1;
    
    if (!verify_required(arg_from, "From:"))
        return 1;
    
    if (!verify_required(arg_to, "To:"))
        return 1;
    
    if (!verify_required(arg_user, "Username"))
        return 1;
    
    if (!verify_required(arg_pass, "Password"))
        return 1;
    
    if (arg_count < 1)
        arg_count = 1;
    
    if (arg_gmail) {
        endpoint = new Geary.Endpoint("smtp.gmail.com", Geary.Smtp.ClientConnection.DEFAULT_PORT_STARTTLS,
            Geary.Endpoint.Flags.STARTTLS | Geary.Endpoint.Flags.GRACEFUL_DISCONNECT,
            Geary.Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    } else {
        Geary.Endpoint.Flags flags = Geary.Endpoint.Flags.GRACEFUL_DISCONNECT;
        if (!arg_no_tls)
            flags |= Geary.Endpoint.Flags.SSL;
        
        endpoint = new Geary.Endpoint(arg_hostname, (uint16) arg_port, flags,
            Geary.Smtp.ClientConnection.DEFAULT_TIMEOUT_SEC);
    }

    stdout.printf("Enabling debug: %s\n", arg_debug.to_string());
    if (arg_debug)
        Geary.Logging.log_to(stdout);

    credentials = new Geary.Credentials(arg_user, arg_pass);
    
    composed_email = new Geary.ComposedEmail(new DateTime.now_local(),
        new Geary.RFC822.MailboxAddresses.single(new Geary.RFC822.MailboxAddress(null, arg_from)));
    composed_email.to = new Geary.RFC822.MailboxAddresses.single(
        new Geary.RFC822.MailboxAddress(null, arg_to));
    
    main_loop = new MainLoop();
    
    main_async.begin(on_main_completed);
    
    main_loop.run();
    
    return ec;
}

