/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Integration.Smtp.ClientSession : TestCase {


    private Configuration config;
    private Geary.Smtp.ClientSession? session;


    public ClientSession(Configuration config) {
        base("Integration.Smtp.ClientSession");
        this.config = config;

        // Break out connecting
        //add_test("session_connect", session_connect);

        add_test("login_password_invalid", login_password_invalid);
        if (config.provider == GMAIL ||
            config.provider == OUTLOOK) {
            add_test("login_oauth2_invalid", login_oauth2_invalid);
        }

        add_test("initiate_session", initiate_session);
        add_test("send_basic_email", send_basic_email);
    }

    public override void set_up() {
        this.session = new Geary.Smtp.ClientSession(
            this.config.target
        );
    }

    public override void tear_down() throws GLib.Error {
        try {
            this.session.logout_async.begin(false, null, this.async_completion);
            this.session.logout_async.end(async_result());
        } catch (GLib.Error err) {
            // Oh well
        }
        this.session = null;
    }

    public void login_password_invalid() throws GLib.Error {
        Geary.Credentials password_creds = new Geary.Credentials(
            PASSWORD,
            "automated-integration-test",
            "deliberately-invalid-password"
        );
        this.session.login_async.begin(
            password_creds, null, this.async_completion
        );
        try {
            this.session.login_async.end(async_result());
            assert_not_reached();
        } catch (Geary.SmtpError.AUTHENTICATION_FAILED err) {
            // All good
        }
    }

    public void login_oauth2_invalid() throws GLib.Error {
        Geary.Credentials oauth2_creds = new Geary.Credentials(
            OAUTH2,
            "automated-integration-test",
            "deliberately-invalid-token"
        );
        this.session.login_async.begin(
            oauth2_creds, null, this.async_completion
        );
        try {
            this.session.login_async.end(async_result());
            assert_not_reached();
        } catch (Geary.SmtpError.AUTHENTICATION_FAILED err) {
            // All good
        }
    }

    public void initiate_session() throws GLib.Error {
        do_connect();
    }

    public void send_basic_email() throws GLib.Error {
        do_connect();

        Geary.RFC822.MailboxAddress return_path =
            new Geary.RFC822.MailboxAddress(
                null, this.config.credentials.user
            );

        this.new_message.begin(
            return_path,
            new Geary.RFC822.MailboxAddress(
                "Geary integration test",
                this.config.credentials.user
            ),
            this.async_completion
        );
        Geary.RFC822.Message message = new_message.end(async_result());

        this.session.send_email_async.begin(
            return_path,
            message,
            null,
            this.async_completion
        );
        this.session.send_email_async.end(async_result());
    }

    private void do_connect() throws GLib.Error {
        this.session.login_async.begin(
            this.config.credentials, null, this.async_completion
        );
        this.session.login_async.end(async_result());
    }

    private async Geary.RFC822.Message new_message(Geary.RFC822.MailboxAddress from,
                                                   Geary.RFC822.MailboxAddress to)
        throws Geary.RFC822.Error {
        Geary.ComposedEmail composed = new Geary.ComposedEmail(
            new GLib.DateTime.now_local(),
            new Geary.RFC822.MailboxAddresses.single(from)
        ).set_to(
            new Geary.RFC822.MailboxAddresses.single(to)
        ).set_subject(
            "Geary integration test subject"
        );
        composed.body_text = "Geary integration test message";

        return yield new Geary.RFC822.Message.from_composed_email(
            composed,
            GMime.utils_generate_message_id(from.domain),
            GMime.EncodingConstraint.7BIT,
            null
        );
    }

}
