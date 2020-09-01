/*
n * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

extern const string _VERSION;

errordomain CommandException {
    USAGE,
    STATE
}

const int IMAP_TIMEOUT_SEC = 60 * 15;

class ImapConsole : Gtk.Window {
    private const int KEEPALIVE_SEC = 60 * 10;

    private Gtk.TextView console = new Gtk.TextView();
    private Gtk.Entry cmdline = new Gtk.Entry();
    private Gtk.Statusbar statusbar = new Gtk.Statusbar();

    private uint statusbar_ctx = 0;
    private uint statusbar_msg_id = 0;

    private Geary.Imap.ClientConnection? cx = null;
    private Gee.HashMap<Geary.Imap.Tag, Geary.Imap.StatusResponse> status_responses = new Gee.HashMap<
        Geary.Imap.Tag, Geary.Imap.StatusResponse>();
    private Geary.Nonblocking.Event recvd_response_event = new Geary.Nonblocking.Event();

    public ImapConsole() {
        title = "IMAP Console";
        destroy.connect(() => { Gtk.main_quit(); });
        set_default_size(800, 600);

        Gtk.Box layout = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);

        console.editable = false;
        Gtk.ScrolledWindow scrolled_console = new Gtk.ScrolledWindow(null, null);
        scrolled_console.add(console);
        scrolled_console.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        layout.pack_start(scrolled_console, true, true, 0);

        cmdline.activate.connect(on_activate);
        layout.pack_start(cmdline, false, false, 0);

        statusbar_ctx = statusbar.get_context_id("status");
        layout.pack_end(statusbar, false, false, 0);

        add(layout);

        cmdline.grab_focus();
    }

    private void on_activate() {
        exec(cmdline.buffer.text);
        cmdline.buffer.delete_text(0, -1);
    }

    private void clear_status() {
        if (statusbar_msg_id == 0)
            return;

        statusbar.remove(statusbar_ctx, statusbar_msg_id);
        statusbar_msg_id = 0;
    }

    private void status(string text) {
        clear_status();

        string msg = text;
        if (!msg.has_suffix(".") && !msg.has_prefix("usage"))
            msg += ".";

        statusbar_msg_id = statusbar.push(statusbar_ctx, msg);
    }

    private void exception(Error err) {
        status(err.message);
    }

    private static string[] cmdnames = {
        "noop",
        "nop",
        "capabililties",
        "caps",
        "connect",
        "unsecure",
        "disconnect",
        "login",
        "logout",
        "id",
        "bye",
        "namespace",
        "list",
        "xlist",
        "examine",
        "create",
        "delete",
        "fetch",
        "uid-fetch",
        "fetch-fields",
        "append",
        "search",
        "uid-search",
        "help",
        "exit",
        "quit",
        "gmail",
        "yahoo",
        "keepalive",
        "status",
        "preview",
        "close"
    };

    private void exec(string input) {
        string[] lines = input.strip().split(";");
        foreach (string line in lines) {
            string[] tokens = line.strip().split(" ");
            if (tokens.length == 0)
                continue;

            string cmd = tokens[0].strip().down();
            string[] args = new string[0];
            for (int ctr = 1; ctr < tokens.length; ctr++) {
                string arg = tokens[ctr].strip();
                if (arg == "\"\"") {
                    args += "";
                } else if (!Geary.String.is_empty(arg)) {
                    args += arg;
                }
            }

            clear_status();

            // TODO: Need to break out the command delegates into their own objects with the
            // human command-names and usage and exec()'s and such; this isn't a long-term approach
            try {
                switch (cmd) {
                    case "noop":
                    case "nop":
                        noop(cmd, args);
                    break;

                    case "capabilities":
                    case "caps":
                        capabilities(cmd, args);
                    break;

                    case "connect":
                    case "unsecure":
                        connect_cmd(cmd, args);
                    break;

                    case "disconnect":
                        disconnect_cmd(cmd, args);
                    break;

                    case "starttls":
                        starttls(cmd, args);
                    break;

                    case "login":
                        login(cmd, args);
                    break;

                    case "logout":
                    case "bye":
                    case "kthxbye":
                        logout(cmd, args);
                    break;

                    case "id":
                        id(cmd, args);
                    break;

                    case "namespace":
                        namespace(cmd, args);
                    break;

                    case "list":
                    case "xlist":
                        list(cmd, args);
                    break;

                    case "examine":
                        examine(cmd, args);
                    break;

                    case "create":
                        create(cmd, args);
                    break;

                    case "delete":
                        @delete(cmd, args);
                    break;

                    case "fetch":
                    case "uid-fetch":
                        fetch(cmd, args);
                    break;

                    case "close":
                        close_cmd(cmd, args);
                    break;

                    case "fetch-fields":
                        fetch_fields(cmd, args);
                    break;

                    case "append":
                        append(cmd, args);
                    break;

                    case "search":
                    case "uid-search":
                        search(cmd, args);
                    break;

                    case "help":
                        foreach (string cmdname in cmdnames)
                            print_console_line(cmdname);
                    break;

                    case "exit":
                    case "quit":
                        quit(cmd, args);
                    break;

                    case "gmail":
                        string[] fake_args = new string[1];
                        fake_args[0] = "imap.gmail.com:993";
                        connect_cmd("connect", fake_args);
                    break;

                    case "yahoo":
                        string[] fake_args = new string[1];
                        fake_args[0] = "imap.mail.yahoo.com:993";
                        connect_cmd("connect", fake_args);
                    break;

                    case "keepalive":
                        keepalive(cmd, args);
                    break;

                    case "status":
                        folder_status(cmd, args);
                    break;

                    case "preview":
                        preview(cmd, args);
                    break;

                    default:
                        status("Unknown command \"%s\"".printf(cmd));
                    break;
                }
            } catch (Error ce) {
                status(ce.message);
            }
        }
    }

    private void check_args(string cmd, string[] args, int count, string? usage) throws CommandException {
        if (args.length != count)
            throw new CommandException.USAGE("usage: %s %s", cmd, usage != null ? usage : "");
    }

    private void check_connected(string cmd, string[] args, int count, string? usage) throws CommandException {
        if (cx == null)
            throw new CommandException.STATE("'connect' required");

        check_args(cmd, args, count, usage);
    }

    private void check_min_args(string cmd, string[] args, int min_count, string? usage) throws CommandException {
        if (args.length < min_count)
            throw new CommandException.USAGE("usage: %s %s", cmd, usage != null ? usage : "");
    }

    private void check_min_connected(string cmd, string[] args, int min_count, string? usage) throws CommandException {
        if (cx == null)
            throw new CommandException.STATE("'connect' required");

        check_min_args(cmd, args, min_count, usage);
    }

    private void capabilities(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, null);

        this.cx.send_command(new Geary.Imap.CapabilityCommand(null));
    }

    private void noop(string cmd, string[] args) throws GLib.Error {
        check_connected(cmd, args, 0, null);

        this.cx.send_command(new Geary.Imap.NoopCommand(null));
    }

    private void connect_cmd(string cmd, string[] args) throws Error {
        if (cx != null)
            throw new CommandException.STATE("'logout' required");

        check_args(cmd, args, 1, "hostname[:port]");

        Geary.TlsNegotiationMethod method = Geary.TlsNegotiationMethod.TRANSPORT;
        if (cmd == "unsecure") {
            method = Geary.TlsNegotiationMethod.START_TLS;
        }

        cx = new Geary.Imap.ClientConnection(
            new Geary.Endpoint(
                new GLib.NetworkAddress(args[0], Geary.Imap.IMAP_TLS_PORT),
                method,
                IMAP_TIMEOUT_SEC
            ),
            new Geary.Imap.Quirks()
        );

        cx.sent_command.connect(on_sent_command);
        cx.received_status_response.connect(on_received_status_response);
        cx.received_server_data.connect(on_received_server_data);
        cx.received_bad_response.connect(on_received_bad_response);

        status("Connecting to %s...".printf(args[0]));
        cx.connect_async.begin(null, on_connected);
    }

    private void on_connected(Object? source, AsyncResult result) {
        try {
            cx.connect_async.end(result);
            status("Connected");
        } catch (Error err) {
            cx = null;

            exception(err);
        }
    }

    private void disconnect_cmd(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, null);

        status("Disconnecting...");
        cx.disconnect_async.begin(null, on_disconnected);
    }

    private void on_disconnected(Object? source, AsyncResult result) {
        try {
            cx.disconnect_async.end(result);
            status("Disconnected");

            cx.sent_command.disconnect(on_sent_command);
            cx.received_status_response.disconnect(on_received_status_response);
            cx.received_server_data.connect(on_received_server_data);
            cx.received_bad_response.disconnect(on_received_bad_response);

            cx = null;
        } catch (Error err) {
            exception(err);
        }
    }

    private void starttls(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, "");

        status("Starting TLS...");
        do_starttls_async.begin(on_do_starttls_async_completed);
    }

    private async void do_starttls_async() throws Error {
        Geary.Imap.StarttlsCommand cmd = new Geary.Imap.StarttlsCommand(null);
        this.cx.send_command(cmd);

        Geary.Imap.StatusResponse response = yield wait_for_response_async(cmd.tag);
        if (response.status == Geary.Imap.Status.OK) {
            yield cx.starttls_async(null);
            status("STARTTLS completed");
        } else {
            status("STARTTLS denied: %s".printf(response.to_string()));
        }
    }

    private void on_do_starttls_async_completed(Object? source, AsyncResult result) {
        try {
            do_starttls_async.end(result);
        } catch (Error err) {
            exception(err);
        }
    }

    private void login(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 2, "user pass");

        status("Logging in...");
        this.cx.send_command(
            new Geary.Imap.LoginCommand(args[0], args[1], null)
        );
    }

    private void logout(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, null);

        status("Logging out...");
        this.cx.send_command(
            new Geary.Imap.LogoutCommand(null)
        );
    }

    private void id(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, null);

        status("Retrieving ID...");

        Gee.HashMap<string, string> fields = new Gee.HashMap<string, string>();
        fields.set("name", "geary-console");
        fields.set("version", _VERSION);

        this.cx.send_command(
            new Geary.Imap.IdCommand(fields, null)
        );
    }

    private void namespace(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, null);

        status("Retrieving NAMESPACE...");
        this.cx.send_command(new Geary.Imap.NamespaceCommand(null));
    }

    private void list(string cmd, string[] args) throws Error {
        check_min_connected(cmd, args, 2, "<reference> <mailbox> [special-use]");

        status("Listing...");
        Geary.Imap.ListReturnParameter? return_param = null;
        if (args.length >= 3 && args[2] == "special-use") {
            return_param = new Geary.Imap.ListReturnParameter();
            return_param.add_special_use();
        }
        this.cx.send_command(
            new Geary.Imap.ListCommand.wildcarded(
                args[0],
                new Geary.Imap.MailboxSpecifier(args[1]),
                (cmd.down() == "xlist"),
                return_param,
                null
            )
        );
    }

    private void examine(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 1, "<mailbox>");

        status("Opening %s read-only".printf(args[0]));
        this.cx.send_command(
            new Geary.Imap.ExamineCommand(
                new Geary.Imap.MailboxSpecifier(args[0]),
                null
            )
        );
    }

    private void create(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 1, "<mailbox>");

        status("Creating %s".printf(args[0]));
        this.cx.send_command(
            new Geary.Imap.CreateCommand(
                new Geary.Imap.MailboxSpecifier(args[0]),
                null
            )
        );
    }

    private void @delete(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 1, "<mailbox>");

        status("Deleting %s".printf(args[0]));
        this.cx.send_command(
            new Geary.Imap.DeleteCommand(
                new Geary.Imap.MailboxSpecifier(args[0]),
                null
            )
        );
    }

    private void fetch(string cmd, string[] args) throws Error {
        check_min_connected(cmd, args, 2, "<message-span> <data-item...>");

        status("Fetching %s".printf(args[0]));

        Geary.Imap.MessageSet msg_set = (cmd.down() == "fetch")
            ? new Geary.Imap.MessageSet.custom(args[0])
            : new Geary.Imap.MessageSet.uid_custom(args[0]);

        Gee.ArrayList<Geary.Imap.FetchDataSpecifier> data_items = new Gee.ArrayList<Geary.Imap.FetchDataSpecifier>();
        for (int ctr = 1; ctr < args.length; ctr++) {
            Geary.Imap.StringParameter stringp = Geary.Imap.StringParameter.get_best_for(args[ctr]);
            Geary.Imap.FetchDataSpecifier data_type = Geary.Imap.FetchDataSpecifier.from_parameter(stringp);
            data_items.add(data_type);
        }

        this.cx.send_command(
            new Geary.Imap.FetchCommand(msg_set, data_items, null, null)
        );
    }

    private void fetch_fields(string cmd, string[] args) throws Error {
        check_min_connected(cmd, args, 2, "<message-span> <field-name...>");

        status("Fetching fields %s".printf(args[0]));

        Geary.Imap.FetchBodyDataSpecifier fields = new Geary.Imap.FetchBodyDataSpecifier(
            Geary.Imap.FetchBodyDataSpecifier.SectionPart.HEADER_FIELDS, null, -1, -1, args[1:args.length]);

        Gee.List<Geary.Imap.FetchBodyDataSpecifier> list = new Gee.ArrayList<Geary.Imap.FetchBodyDataSpecifier>();
        list.add(fields);

        this.cx.send_command(
            new Geary.Imap.FetchCommand(
                new Geary.Imap.MessageSet.custom(args[0]), null, list, null
            )
        );
    }

    private void append(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 2, "<mailbox> <filename>");

        status("Appending %s to %s".printf(args[1], args[0]));

        this.cx.send_command(
            new Geary.Imap.AppendCommand(
                new Geary.Imap.MailboxSpecifier(args[0]),
                null,
                null,
                new Geary.Memory.FileBuffer(File.new_for_path(args[1]), true),
                null
            )
        );
    }

    private void search(string cmd, string[] args) throws Error {
        check_min_connected(cmd, args, 1, "<arg> ...");

        status("Searching");

        Geary.Imap.SearchCriteria criteria = new Geary.Imap.SearchCriteria();
        foreach (string arg in args)
            criteria.and(new Geary.Imap.SearchCriterion.simple(arg));

        Geary.Imap.SearchCommand search;
        if (cmd == "uid-search")
            search = new Geary.Imap.SearchCommand.uid(criteria, null);
        else
            search = new Geary.Imap.SearchCommand(criteria, null);

        this.cx.send_command(search);
    }

    private void close_cmd(string cmd, string[] args) throws Error {
        check_connected(cmd, args, 0, null);

        status("Closing");

        this.cx.send_command(
            new Geary.Imap.CloseCommand(null)
        );
    }

    private void folder_status(string cmd, string[] args) throws Error {
        check_min_connected(cmd, args, 2, "<folder> <data-item...>");

        status("Status %s".printf(args[0]));

        Geary.Imap.StatusDataType[] data_items = new Geary.Imap.StatusDataType[0];
        for (int ctr = 1; ctr < args.length; ctr++) {
            Geary.Imap.StringParameter stringp = Geary.Imap.StringParameter.get_best_for(args[ctr]);
            data_items += Geary.Imap.StatusDataType.from_parameter(stringp);
        }

        this.cx.send_command(
            new Geary.Imap.StatusCommand(
                new Geary.Imap.MailboxSpecifier(args[0]),
                data_items,
                null
            )
        );
    }

    private void preview(string cmd, string[] args) throws Error {
        check_min_connected(cmd, args, 1, "<message-span>");

        status("Preview %s".printf(args[0]));

        Geary.Imap.FetchBodyDataSpecifier preview_data_type = new Geary.Imap.FetchBodyDataSpecifier.peek(
            Geary.Imap.FetchBodyDataSpecifier.SectionPart.NONE, { 1 }, 0, Geary.Email.MAX_PREVIEW_BYTES,
            null);

        Gee.ArrayList<Geary.Imap.FetchBodyDataSpecifier> list = new Gee.ArrayList<Geary.Imap.FetchBodyDataSpecifier>();
        list.add(preview_data_type);

        this.cx.send_command(
            new Geary.Imap.FetchCommand(
                new Geary.Imap.MessageSet.custom(args[0]), null, list, null
            )
        );
    }

    private void quit(string cmd, string[] args) throws Error {
        Gtk.main_quit();
    }

    private bool keepalive_on = false;

    private void keepalive(string cmd, string[] args) throws Error {
        if (keepalive_on) {
            status("Keepalive already active.");

            return;
        }

        check_connected(cmd, args, 0, null);

        keepalive_on = true;
        Timeout.add_seconds(KEEPALIVE_SEC, on_keepalive);

        status("Keepalive on.");
    }

    private bool on_keepalive() {
        try {
            noop("noop", new string[0]);
        } catch (Error err) {
            status("Keepalive failed, halted: %s".printf(err.message));

            keepalive_on = false;
        }

        return keepalive_on;
    }

    private void print_console_line(string text) {
        append_to_console("[C] ");
        append_to_console(text);
        append_to_console("\n");
    }

    private void on_sent_command(Geary.Imap.Command cmd) {
        append_to_console("[L] ");
        append_to_console(cmd.to_string());
        append_to_console("\n");
    }

    private void on_received_status_response(Geary.Imap.StatusResponse status_response) {
        append_to_console("[R] ");
        append_to_console(status_response.to_string());
        append_to_console("\n");

        // TODO: This means that responses will grow without bounds without some process of
        // timing-out old unharvested responses
        status_responses.set(status_response.tag, status_response);
        recvd_response_event.blind_notify();
    }

    private async Geary.Imap.StatusResponse wait_for_response_async(Geary.Imap.Tag tag) throws Error {
        for (;;) {
            Geary.Imap.StatusResponse? response = status_responses.get(tag);
            if (response != null)
                return response;

            yield recvd_response_event.wait_async();
        }
    }

    private void on_received_server_data(Geary.Imap.ServerData server_data) {
        append_to_console("[D] ");
        append_to_console(server_data.to_string());
        append_to_console("\n");
    }

    private void on_received_bad_response(Geary.Imap.RootParameters root, Geary.ImapError err) {
        append_to_console("[E] ");
        append_to_console(err.message);
        append_to_console(": ");
        append_to_console(root.to_string());
        append_to_console("\n");
    }

    private void append_to_console(string text) {
        Gtk.TextIter iter;
        console.buffer.get_iter_at_offset(out iter, -1);
        console.buffer.insert(ref iter, text, -1);
    }
}

void main(string[] args) {
    Gtk.init(ref args);

    Geary.Logging.init();
    Geary.Logging.log_to(stdout);

    ImapConsole console = new ImapConsole();
    console.show_all();

    Gtk.main();
}
