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
        add_test("load_context_edit", load_context_edit);
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
                Folks.IndividualAggregator.dup(),
                new Application.AvatarStore()
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

    public void load_context_edit() throws GLib.Error {
        var widget = new Widget(this.application, this.config, this.account);

        widget.load_context.begin(
            EDIT, load_email(), null, this.async_completion
        );
        widget.load_context.end(async_result());

        assert_equal(widget.to, "Charlie <charlie@example.net>");
        assert_equal(widget.cc, "Dave <dave@example.net>");
        assert_equal(widget.bcc, "Eve <eve@example.net>");
        assert_equal(widget.reply_to, "Alice: Personal Account <alice@example.org>");
        assert_equal(widget.subject, "Re: Basic text/plain message");
    }

    private Geary.Email load_email()
        throws GLib.Error {
        var message = new Geary.RFC822.Message.from_buffer(
            new Geary.Memory.StringBuffer(MESSAGE.replace("\n","\r\n"))
        );
        return new Geary.Email.from_message(
            new Mock.EmailIdentifer(0), message
        );
    }

    private const string MESSAGE = """From: Alice <alice@example.net>
Sender: Bob <bob@example.net>
To: Charlie <charlie@example.net>
CC: Dave <dave@example.net>
BCC: Eve <eve@example.net>
Reply-To: "Alice: Personal Account" <alice@example.org>
Subject: Re: Basic text/plain message
Date: Fri, 21 Nov 1997 10:01:10 -0600
Message-ID: <3456@example.net>
In-Reply-To: <1234@local.machine.example>
References: <1234@local.machine.example>
X-Mailer: Geary Test Suite 1.0

This is the first line.

This is the second line.

""";

}
