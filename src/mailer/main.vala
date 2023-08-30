/* Copyright 2016 Software Freedom Conservancy Inc.
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
        Geary.RFC822.Message msg;

        if (arg_full_file != null) {
            debug("%s", arg_full_file);
            msg = new Geary.RFC822.Message.from_buffer(new Geary.Memory.FileBuffer(
                File.new_for_path(arg_full_file), true));
        } else {
            string subj_msg = "#%d".printf(ctr + 1);
            composed_email.set_subject(subj_msg);

            if (Geary.String.is_empty(arg_file)) {
                composed_email.body_text = subj_msg;
            } else {
                string contents;
                FileUtils.get_contents(arg_file, out contents);

                composed_email.body_text = contents;
            }

            if (!Geary.String.is_empty(arg_html)) {
                string contents;
                FileUtils.get_contents(arg_html, out contents);

                composed_email.body_html = contents;
            }

            msg = yield new Geary.RFC822.Message.from_composed_email(
                composed_email, null, GMime.EncodingConstraint.7BIT, null
            );
        }

        stdout.printf("\n\n%s\n\n", msg.to_string());

        yield session.send_email_async(msg.from.get(0), msg);

        stdout.printf("Sent email #%d\n", ctr);
    }

    Geary.Smtp.Response? logout = yield session.logout_async(false);
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
string? arg_file = null;
string? arg_html = null;
string? arg_full_file = null;
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
    { "count",  'c',    0,  OptionArg.INT,      ref arg_count,  "Number of emails to send (not applied for file-full)", null },
    { "file-body",'i',  0,  OptionArg.STRING,   ref arg_file,   "File to send as body (must be RFC 822 ready!)", "<filename>"},
    { "html-body",'m',  0,  OptionArg.STRING,   ref arg_html,   "HTML file to be sent as body", "<filename>" },
    { "file-full",0,    0,  OptionArg.STRING,   ref arg_full_file, "File to send as full message (headers and body, must be RFC822 ready!, --from and --to ignored)", "<filename>"},
    { null }
};

const int SMTP_TIMEOUT_SEC = 30;

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

    if (arg_full_file == null && !verify_required(arg_from, "From:"))
        return 1;

    if (arg_full_file == null && !verify_required(arg_to, "To:"))
        return 1;

    if (!verify_required(arg_user, "Username"))
        return 1;

    if (!verify_required(arg_pass, "Password"))
        return 1;

    if (arg_count < 1)
        arg_count = 1;

    if (arg_gmail) {
        endpoint = new Geary.Endpoint(
            new GLib.NetworkAddress("smtp.gmail.com", Geary.Smtp.SUBMISSION_PORT),
            Geary.TlsNegotiationMethod.START_TLS,
            SMTP_TIMEOUT_SEC
        );
    } else {
        Geary.TlsNegotiationMethod method = Geary.TlsNegotiationMethod.TRANSPORT;
        if (arg_no_tls) {
            method = Geary.TlsNegotiationMethod.START_TLS;
        }
        endpoint = new Geary.Endpoint(
            new GLib.NetworkAddress(arg_hostname, (uint16) arg_port),
            method,
            SMTP_TIMEOUT_SEC
        );
    }

    stdout.printf("Enabling debug: %s\n", arg_debug.to_string());
    Geary.Logging.init();
    if (arg_debug) {
        Geary.Logging.log_to(stdout);
        GLib.Log.set_writer_func(Geary.Logging.default_log_writer);
    }

    Geary.RFC822.init();

    credentials = new Geary.Credentials(
        Geary.Credentials.Method.PASSWORD, arg_user, arg_pass
    );

    if (arg_full_file == null) {
        composed_email = new Geary.ComposedEmail(
            new GLib.DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.single(new Geary.RFC822.MailboxAddress(null, arg_from))
        ).set_to(
            new Geary.RFC822.MailboxAddresses.single(new Geary.RFC822.MailboxAddress(null, arg_to))
        );
    }

    main_loop = new MainLoop();

    main_async.begin(on_main_completed);

    main_loop.run();

    return ec;
}

