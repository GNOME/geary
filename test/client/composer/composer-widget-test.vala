/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Composer.WidgetTest : TestCase {


    private class MockApplicationInterface :
        GLib.Object,
        Application.AccountInterface,
        ApplicationInterface,
        ValaUnit.TestAssertions,
        ValaUnit.MockObject {


        protected Gee.Queue<ValaUnit.ExpectedCall> expected {
            get; set; default = new Gee.LinkedList<ValaUnit.ExpectedCall>();
        }


        internal Application.AccountContext? get_context_for_account(Geary.AccountInformation account)  {
            try {
                return object_call<Application.AccountContext?>(
                    "get_account_contexts",
                    {account},
                    null
                );
            } catch (GLib.Error err) {
                // fine
                return null;
            }
        }

        internal Gee.Collection<Application.AccountContext> get_account_contexts() {
            try {
                return object_call<Gee.Collection<Application.AccountContext>>(
                    "get_account_contexts",
                    {},
                    Gee.Collection.empty()
                );
            } catch (GLib.Error err) {
                // fine
                return Gee.Collection.empty();
            }
        }

        public void report_problem(Geary.ProblemReport report) {
            try {
                void_call("report_problem", {report});
            } catch (GLib.Error err) {
                // fine
            }
        }

        internal async void send_composed_email(Widget composer) {
            try {
                void_call("send_composed_email", {composer});
            } catch (GLib.Error err) {
                // fine
            }
        }

        internal async void save_composed_email(Widget composer) {
            try {
                void_call("save_composed_email", {composer});
            } catch (GLib.Error err) {
                // fine
            }
        }

        internal async void discard_composed_email(Widget composer) {
            try {
                void_call("discard_composed_email", {composer});
            } catch (GLib.Error err) {
                // fine
            }
        }

    }


    private Application.AccountContext? account = null;
    private ApplicationInterface? application = null;
    private Application.Configuration? config = null;


    public WidgetTest() {
        base("Composer.WidgetTest");
        add_test("load_empty_body", load_empty_body);
        add_test("load_empty_body_to", load_empty_body_to);
        add_test("load_mailto", load_mailto);
        add_test("load_mailto_empty", load_mailto_empty);
        add_test("load_context_edit", load_context_edit);
        add_test("load_context_reply_sender", load_context_reply_sender);
        add_test("load_context_reply_sender_with_reply_to", load_context_reply_sender_with_reply_to);
        add_test("load_context_reply_all_to_account", load_context_reply_all_to_account);
        add_test("load_context_reply_all_cc_account", load_context_reply_all_cc_account);
        add_test("load_context_reply_all_to_other", load_context_reply_all_to_other);
        add_test("load_context_reply_all_to_other_with_reply_to", load_context_reply_all_to_other_with_reply_to);
        add_test("load_context_forward", load_context_forward);
        add_test("to_composed_email", to_composed_email);
    }

    public override void set_up() {
        this.application = new MockApplicationInterface();

        this.config = new Application.Configuration(Application.Client.SCHEMA_ID);

        var info = new Geary.AccountInformation(
            "account_01",
            Geary.ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
            new Geary.RFC822.MailboxAddress(null, "test1@example.com")
        );
        var mock_account = new Mock.Account(info);
        this.account = new Application.AccountContext(
            mock_account,
            new Geary.App.SearchFolder(
                mock_account,
                new Geary.FolderRoot("", false)
            ),
            new Geary.App.EmailStore(mock_account),
            new Application.ContactStore(
                mock_account,
                Folks.IndividualAggregator.dup()
            )
        );
    }

    public override void tear_down() {
        this.application = null;
        this.config = null;
        this.account = null;
    }

    public void load_empty_body() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        widget.load_empty_body.begin(null, this.async_completion);
        widget.load_empty_body.end(async_result());
        assert_equal(widget.to, "");
    }

    public void load_empty_body_to() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        widget.load_empty_body.begin(
            new Geary.RFC822.MailboxAddress(null, "empty_to@example.com"),
            this.async_completion
        );
        widget.load_empty_body.end(async_result());
        assert_equal(widget.to, "empty_to@example.com");
    }

    public void load_mailto() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);

        widget.load_mailto.begin(
            "mailto:mailto@example.com", this.async_completion
        );
        widget.load_mailto.end(async_result());

        assert_equal(widget.to, "mailto@example.com");
    }

    public void load_mailto_empty() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);

        widget.load_mailto.begin("mailto:", this.async_completion);
        widget.load_mailto.end(async_result());

        assert_equal(widget.to, "");
    }

    public void load_context_edit() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_WITH_REPLY_TO);

        var mock_account = (Mock.Account) this.account.account;
        var search_call = mock_account.expect_call("local_search_message_id_async");

        widget.load_context.begin(EDIT, email, null, this.async_completion);
        widget.load_context.end(async_result());

        mock_account.assert_expectations();
        var search_arg = search_call.called_arg<Geary.RFC822.MessageID>(0);
        assert_equal(
            search_arg.to_rfc822_string(),
            "<1234@local.machine.example>"
        );

        assert_equal(widget.to, "Charlie <charlie@example.net>");
        assert_equal(widget.cc, "Dave <dave@example.net>");
        assert_equal(widget.bcc, "Eve <eve@example.net>");
        assert_equal(widget.reply_to, "Alice: Personal Account <alice@example.org>");
        assert_equal(widget.subject, "Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<1234@local.machine.example>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example>"
        );
    }

    public void load_context_reply_sender() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_NO_REPLY_TO);

        widget.load_context.begin(REPLY_SENDER, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Alice <alice@example.net>");
        assert_equal(widget.cc, "");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Re: Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<3456@example.net>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example> <3456@example.net>"
        );
    }

    public void load_context_reply_sender_with_reply_to() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_WITH_REPLY_TO);

        widget.load_context.begin(REPLY_SENDER, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Alice: Personal Account <alice@example.org>");
        assert_equal(widget.cc, "");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Re: Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<3456@example.net>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example> <3456@example.net>"
        );
    }

    public void load_context_reply_all_to_account() throws GLib.Error {
        // If the message's To includes the account's primary mailbox,
        // then that should not be included in the CC
        this.account.account.information.replace_sender(
            0, new Geary.RFC822.MailboxAddress("Charlie", "charlie@example.net")
        );

        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_NO_REPLY_TO);

        widget.load_context.begin(REPLY_ALL, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Alice <alice@example.net>");
        assert_equal(widget.cc, "Dave <dave@example.net>");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Re: Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<3456@example.net>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example> <3456@example.net>"
        );
    }

    public void load_context_reply_all_cc_account() throws GLib.Error {
        // If the message's CC includes the account's primary mailbox,
        // then that should not be included in the CC either
        this.account.account.information.replace_sender(
            0, new Geary.RFC822.MailboxAddress("Dave", "dave@example.net")
        );

        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_NO_REPLY_TO);

        widget.load_context.begin(REPLY_ALL, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Alice <alice@example.net>");
        assert_equal(widget.cc, "Charlie <charlie@example.net>");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Re: Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<3456@example.net>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example> <3456@example.net>"
        );
    }

    public void load_context_reply_all_to_other() throws GLib.Error {
        // Neither the message's To or CC contains the account's
        // primary mailbox, so CC should include all of the addresses
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_NO_REPLY_TO);

        widget.load_context.begin(REPLY_ALL, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Alice <alice@example.net>");
        assert_equal(widget.cc, "Charlie <charlie@example.net>, Dave <dave@example.net>");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Re: Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<3456@example.net>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example> <3456@example.net>"
        );
    }

    public void load_context_reply_all_to_other_with_reply_to() throws GLib.Error {
        // Neither the message's To or CC contains the account's
        // primary mailbox, so CC should include all of the addresses
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_WITH_REPLY_TO);

        widget.load_context.begin(REPLY_ALL, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Alice: Personal Account <alice@example.org>");
        assert_equal(widget.cc, "Charlie <charlie@example.net>, Alice <alice@example.net>, Dave <dave@example.net>");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Re: Basic text/plain message");
        assert_equal(
            widget.in_reply_to.to_rfc822_string(),
            "<3456@example.net>"
        );
        assert_equal(
            widget.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example> <3456@example.net>"
        );
    }

    public void load_context_forward() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_NO_REPLY_TO);

        widget.load_context.begin(FORWARD, email, null, this.async_completion);
        widget.load_context.end(async_result());

        assert_equal(widget.to, "");
        assert_equal(widget.cc, "");
        assert_equal(widget.bcc, "");
        assert_equal(widget.reply_to, "");
        assert_equal(widget.subject, "Fwd: Basic text/plain message");
        assert_equal(widget.in_reply_to.to_rfc822_string(), "", "In-Reply-To");
        assert_equal(
            widget.references.to_rfc822_string(),
            "<3456@example.net>",
            "References"
        );
    }

    public void to_composed_email() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);
        var email = load_email(MESSAGE_WITH_REPLY_TO);

        var mock_account = (Mock.Account) this.account.account;
        mock_account.expect_call("local_search_message_id_async");

        widget.load_context.begin(EDIT, email, null, this.async_completion);
        widget.load_context.end(async_result());
        mock_account.assert_expectations();

        widget.to_composed_email.begin(null, false, this.async_completion);
        Geary.ComposedEmail composed = widget.to_composed_email.end(async_result());

        assert_equal(
            composed.to.to_rfc822_string(),
            "Charlie <charlie@example.net>"
        );
        assert_equal(
            composed.cc.to_rfc822_string(),
            "Dave <dave@example.net>"
        );
        assert_equal(
            composed.bcc.to_rfc822_string(),
            "Eve <eve@example.net>"
        );
        // XXX this checked without the "Alice: " prefix, since
        // Composer.ContactEntry uses
        // RFC822.MailboxAddresses.from_rfc822_string() to parse its
        // entry text, and that strips off the colon and anything in
        // front since it's an invalid char.
        assert_equal(
            composed.reply_to.to_rfc822_string(),
            "Personal Account <alice@example.org>"
        );
        assert_equal(
            composed.subject.to_rfc822_string(),
            "Basic text/plain message"
        );
        assert_equal(
            composed.in_reply_to.to_rfc822_string(),
            "<1234@local.machine.example>"
        );
        assert_equal(
            composed.references.to_rfc822_string(),
            "<1234@local.machine.example> <5678@local.machine.example>"
        );
    }

    private Geary.Email load_email(string text)
        throws GLib.Error {
        var message = new Geary.RFC822.Message.from_buffer(
            new Geary.Memory.StringBuffer(text.replace("\n","\r\n"))
        );
        return new Geary.Email.from_message(
            new Mock.EmailIdentifer(0), message
        );
    }

    private const string MESSAGE_NO_REPLY_TO = """From: Alice <alice@example.net>
Sender: Bob <bob@example.net>
To: Charlie <charlie@example.net>
CC: Dave <dave@example.net>
BCC: Eve <eve@example.net>
Subject: Basic text/plain message
Date: Fri, 21 Nov 1997 10:01:10 -0600
Message-ID: <3456@example.net>
In-Reply-To: <1234@local.machine.example>
References: <1234@local.machine.example> <5678@local.machine.example>
X-Mailer: Geary Test Suite 1.0

This is the first line.

This is the second line.

""";

    private const string MESSAGE_WITH_REPLY_TO = """From: Alice <alice@example.net>
Sender: Bob <bob@example.net>
To: Charlie <charlie@example.net>
CC: Dave <dave@example.net>
BCC: Eve <eve@example.net>
Reply-To: "Alice: Personal Account" <alice@example.org>
Subject: Basic text/plain message
Date: Fri, 21 Nov 1997 10:01:10 -0600
Message-ID: <3456@example.net>
In-Reply-To: <1234@local.machine.example>
References: <1234@local.machine.example> <5678@local.machine.example>
X-Mailer: Geary Test Suite 1.0

This is the first line.

This is the second line.

""";

}
