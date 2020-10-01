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
        add_test("connect_with_capabilities", connect_with_capabilities);
        if (GLib.Test.slow()) {
            add_test("connect_timeout", connect_timeout);
        }
        add_test("login", login);
        add_test("login_with_capabilities", login_with_capabilities);
        add_test("logout", logout);
        add_test("login_logout", login_logout);
        add_test("initiate_request_capabilities", initiate_request_capabilities);
        add_test("initiate_implicit_capabilities", initiate_implicit_capabilities);
        add_test("initiate_namespace", initiate_namespace);
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

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void connect_with_capabilities() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK [CAPABILITY IMAP4rev1] localhost test server ready"
        );
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());

        assert_true(test_article.capabilities.supports_imap4rev1());

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(result.succeeded);
    }

    public void connect_timeout() throws GLib.Error {
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());

        GLib.Timer timer = new GLib.Timer();
        timer.start();
        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        try {
            test_article.connect_async.end(async_result());
            assert_not_reached();
        } catch (GLib.IOError.TIMED_OUT err) {
            assert_within(timer.elapsed(), CONNECT_TIMEOUT, CONNECT_TIMEOUT * 0.5);
        }

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(result.succeeded);
    }

    public void login_with_capabilities() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 login test password");
        this.server.add_script_line(
            SEND_LINE, "a001 OK [CAPABILITY IMAP4rev1] ohhai"
        );
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        test_article.login_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_completion
        );
        test_article.login_async.end(async_result());

        assert_true(test_article.capabilities.supports_imap4rev1());

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void login() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 login test password");
        this.server.add_script_line(SEND_LINE, "a001 OK ohhai");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.login_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_completion
        );
        test_article.login_async.end(async_result());
        assert_true(test_article.protocol_state == AUTHORIZED);

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

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

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.logout_async.begin(null, this.async_completion);
        test_article.logout_async.end(async_result());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

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

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.login_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_completion
        );
        test_article.login_async.end(async_result());
        assert_true(test_article.protocol_state == AUTHORIZED);

        test_article.logout_async.begin(null, this.async_completion);
        test_article.logout_async.end(async_result());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void initiate_request_capabilities() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 capability");
        this.server.add_script_line(SEND_LINE, "* CAPABILITY IMAP4rev1 LOGIN");
        this.server.add_script_line(SEND_LINE, "a001 OK enjoy");
        this.server.add_script_line(RECEIVE_LINE, "a002 login test password");
        this.server.add_script_line(SEND_LINE, "a002 OK ohhai");
        this.server.add_script_line(RECEIVE_LINE, "a003 capability");
        this.server.add_script_line(SEND_LINE, "* CAPABILITY IMAP4rev1");
        this.server.add_script_line(SEND_LINE, "a003 OK thanks");
        this.server.add_script_line(RECEIVE_LINE, "a004 LIST \"\" INBOX");
        this.server.add_script_line(SEND_LINE, "* LIST (\\HasChildren) \".\" Inbox");
        this.server.add_script_line(SEND_LINE, "a004 OK there");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.initiate_session_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_completion
        );
        test_article.initiate_session_async.end(async_result());

        assert_true(test_article.capabilities.supports_imap4rev1());
        assert_false(test_article.capabilities.has_capability("AUTH"));
        assert_equal<int?>(test_article.capabilities.revision, 2);

        assert_equal(test_article.inbox.mailbox.name, "Inbox");
        assert_true(test_article.inbox.mailbox.is_inbox);

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void initiate_implicit_capabilities() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE, "* OK [CAPABILITY IMAP4rev1 LOGIN] localhost test server ready"
        );
        this.server.add_script_line(RECEIVE_LINE, "a001 login test password");
        this.server.add_script_line(SEND_LINE, "a001 OK [CAPABILITY IMAP4rev1] ohhai");
        this.server.add_script_line(RECEIVE_LINE, "a002 LIST \"\" INBOX");
        this.server.add_script_line(SEND_LINE, "* LIST (\\HasChildren) \".\" Inbox");
        this.server.add_script_line(SEND_LINE, "a002 OK there");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.initiate_session_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_completion
        );
        test_article.initiate_session_async.end(async_result());

        assert_true(test_article.capabilities.supports_imap4rev1());
        assert_false(test_article.capabilities.has_capability("AUTH"));
        assert_equal<int?>(test_article.capabilities.revision, 2);

        assert_equal(test_article.inbox.mailbox.name, "Inbox");
        assert_true(test_article.inbox.mailbox.is_inbox);

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

        TestServer.Result result = this.server.wait_for_script(this.main_loop);
        assert_true(
            result.succeeded,
            result.error != null ? result.error.message : "Server result failed"
        );
    }

    public void initiate_namespace() throws GLib.Error {
        this.server.add_script_line(
            SEND_LINE,
            "* OK [CAPABILITY IMAP4rev1 LOGIN] localhost test server ready"
        );
        this.server.add_script_line(
            RECEIVE_LINE, "a001 login test password"
        );
        this.server.add_script_line(
            SEND_LINE, "a001 OK [CAPABILITY IMAP4rev1 NAMESPACE] ohhai"
        );
        this.server.add_script_line(
            RECEIVE_LINE, "a002 LIST \"\" INBOX"
        );
        this.server.add_script_line(
            SEND_LINE, "* LIST (\\HasChildren) \".\" Inbox"
        );
        this.server.add_script_line(
            SEND_LINE, "a002 OK there"
        );
        this.server.add_script_line(
            RECEIVE_LINE, "a003 NAMESPACE"
        );
        this.server.add_script_line(
            SEND_LINE,
            """* NAMESPACE (("INBOX." ".")) (("user." ".")) (("shared." "."))"""
        );
        this.server.add_script_line(SEND_LINE, "a003 OK there");
        this.server.add_script_line(WAIT_FOR_DISCONNECT, "");

        var test_article = new ClientSession(new_endpoint(), new Quirks());
        assert_true(test_article.protocol_state == NOT_CONNECTED);

        test_article.connect_async.begin(
            CONNECT_TIMEOUT, null, this.async_completion
        );
        test_article.connect_async.end(async_result());
        assert_true(test_article.protocol_state == UNAUTHORIZED);

        test_article.initiate_session_async.begin(
            new Credentials(PASSWORD, "test", "password"),
            null,
            this.async_completion
        );
        test_article.initiate_session_async.end(async_result());

        assert_equal<int?>(test_article.get_personal_namespaces().size, 1);
        assert_equal(
            test_article.get_personal_namespaces()[0].prefix,
            "INBOX."
        );

        assert_equal<int?>(test_article.get_shared_namespaces().size, 1);
        assert_equal(
            test_article.get_shared_namespaces()[0].prefix,
            "shared."
        );

        assert_equal<int?>(test_article.get_other_users_namespaces().size, 1);
        assert_equal(
            test_article.get_other_users_namespaces()[0].prefix,
            "user."
        );

        test_article.disconnect_async.begin(null, this.async_completion);
        test_article.disconnect_async.end(async_result());

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
