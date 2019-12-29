/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.ClientSessionTest : TestCase {

    private const uint CONNECT_TIMEOUT = 2;

    private TestServer? server = null;


    public ClientSessionTest() {
        base("Geary.Imap.ClientSessionTest");
        add_test("connect_disconnect", connect_disconnect);
        if (GLib.Test.slow()) {
            add_test("connect_timeout", connect_timeout);
        }
        add_test("login", login);
        add_test("logout", logout);
        add_test("login_logout", login_logout);
    }

    protected override void set_up() throws GLib.Error {
        this.server = new TestServer();
    }

    protected override void tear_down() {
        this.server.stop();
        this.server = null;
    }

    public void connect_disconnect() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_complete_full
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == UNAUTHORIZED);

        test_article.disconnect_async.begin(null, this.async_complete_full);
        test_article.disconnect_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void connect_timeout() throws GLib.Error {
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint());

        GLib.Timer timer = new GLib.Timer();
        timer.start();
        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_complete_full
        );
        try {
            test_article.connect_async.end(async_result());
            assert_not_reached();
        } catch (GLib.IOError.TIMED_OUT err) {
            assert_double(timer.elapsed(), CONNECT_TIMEOUT, 0.5);
        }

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(result.succeeded);
    }

    public void login() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 login test password");
        this.server.add_script_line(SEND_LINE, "a001 OK ohhai");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_complete_full
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == UNAUTHORIZED);

        test_article.login_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_complete_full
        );
        test_article.login_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == AUTHORIZED);

        test_article.disconnect_async.begin(null, this.async_complete_full);
        test_article.disconnect_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void logout() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 logout");
        this.server.add_script_line(SEND_LINE, "* BYE fine");
        this.server.add_script_line(SEND_LINE, "a001 OK laters");
        this.server.add_script_line(DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_complete_full
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == UNAUTHORIZED);

        test_article.logout_async.begin(null, this.async_complete_full);
        test_article.logout_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void login_logout() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 login test password");
        this.server.add_script_line(SEND_LINE, "a001 OK ohhai");
        this.server.add_script_line(RECEIVE_LINE, "a002 logout");
        this.server.add_script_line(SEND_LINE, "* BYE fine");
        this.server.add_script_line(SEND_LINE, "a002 OK laters");
        this.server.add_script_line(DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_complete_full
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == UNAUTHORIZED);

        test_article.login_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_complete_full
        );
        test_article.login_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == AUTHORIZED);

        test_article.logout_async.begin(null, this.async_complete_full);
        test_article.logout_async.end(async_result());
        assert_true(test_article.get_protocol_state(null) == NOT_CONNECTED);

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    protected Endpoint new_endpoint() {
        return new Endpoint(this.server.get_client_address(), NONE, 10);
    }

}
