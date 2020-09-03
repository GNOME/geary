/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.ClientConnectionTest : TestCase {


    private class TestCommand : Command {

        public TestCommand() {
            base("TEST", null, null);
        }

    }

    private TestServer? server = null;


    public ClientConnectionTest() {
        base("Geary.Imap.ClientConnectionTest");
        add_test("connect_disconnect", connect_disconnect);
        if (GLib.Test.slow()) {
            add_test("idle", idle);
            add_test("command_timeout", command_timeout);
        }
    }

    protected override void set_up() throws GLib.Error {
        this.server = new TestServer();
    }

    protected override void tear_down() {
        this.server.stop();
        this.server = null;
    }

    public void connect_disconnect() throws GLib.Error {
        var test_article = new ClientConnection(new_endpoint(), new Quirks());

        test_article.connect_async.begin(null, this.async_completion);
        test_article.connect_async.end(async_result());

        assert_non_null(test_article.get_remote_address());
        assert_non_null(test_article.get_local_address());

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        assert_null(test_article.get_remote_address());
        assert_null(test_article.get_local_address());

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert(result.succeeded);
    }

    public void idle() throws GLib.Error {
        this.server.add_script_line(RECEIVE_LINE, "a001 IDLE");
        this.server.add_script_line(SEND_LINE, "+ idling");
        this.server.add_script_line(RECEIVE_LINE, "DONE");
        this.server.add_script_line(SEND_LINE, "a001 OK Completed");
        this.server.add_script_line(RECEIVE_LINE, "a002 TEST");
        this.server.add_script_line(SEND_LINE, "a002 OK Looks good");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        const int COMMAND_TIMEOUT = 1;
        const int IDLE_TIMEOUT = 1;

        var test_article = new ClientConnection(
            new_endpoint(), new Quirks(), COMMAND_TIMEOUT, IDLE_TIMEOUT
        );
        test_article.connect_async.begin(null, this.async_completion);
        test_article.connect_async.end(async_result());

        assert_false(test_article.is_in_idle(), "Initial idle state");
        test_article.enable_idle_when_quiet(true);
        assert_false(test_article.is_in_idle(), "Post-enabled idle state");

        // Wait for idle to kick in
        GLib.Timer timer = new GLib.Timer();
        timer.start();
        while (!test_article.is_in_idle() &&
               timer.elapsed() < IDLE_TIMEOUT * 2) {
            this.main_loop.iteration(false);
        }

        assert_true(test_article.is_in_idle(), "Entered idle");

        // Ensure idle outlives command timeout
        timer.start();
        while (timer.elapsed() < COMMAND_TIMEOUT * 2) {
            this.main_loop.iteration(false);
        }

        assert_true(test_article.is_in_idle(), "Post idle command timeout");

        var command = new TestCommand();
        test_article.send_command(command);
        command.wait_until_complete.begin(null, this.async_completion);
        command.wait_until_complete.end(async_result());

        assert_false(test_article.is_in_idle(), "Post test command");

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert(result.succeeded);
    }

    public void command_timeout() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 TEST");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        const int TIMEOUT = 2;

        bool sent = false;
        bool recv_fail = false;
        bool timed_out = false;

        var test_article = new ClientConnection(
            new_endpoint(), new Quirks(), TIMEOUT
        );
        test_article.sent_command.connect(() => { sent = true; });
        test_article.receive_failure.connect(() => { recv_fail = true; });
        test_article.connect_async.begin(null, this.async_completion);
        test_article.connect_async.end(async_result());

        var command = new TestCommand();
        command.response_timed_out.connect(() => { timed_out = true; });

        test_article.send_command(command);

        GLib.Timer timer = new GLib.Timer();
        timer.start();
        while (!timed_out && timer.elapsed() < TIMEOUT * 2) {
            this.main_loop.iteration(false);
        }

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        assert_true(sent, "connection.sent_command");
        assert_true(recv_fail, "command.receive_failure");
        assert_true(timed_out, "command.response_timed_out");

        debug("Waiting for server...");

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(result.succeeded);
    }

    protected Endpoint new_endpoint() {
        return new Endpoint(this.server.get_client_address(), NONE, 10);
    }

}
