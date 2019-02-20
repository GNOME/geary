/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.AccountInformationTest : TestCase {


    public AccountInformationTest() {
        base("Geary.AccountInformationTest");
        add_test("test_save_sent_defaults", test_save_sent_defaults);
        add_test("test_sender_mailboxes", test_sender_mailboxes);
    }

    public void test_save_sent_defaults() throws GLib.Error {
        assert_true(
            new AccountInformation(
                "test",
                ServiceProvider.OTHER,
                new MockCredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_false(
            new AccountInformation(
                "test",
                ServiceProvider.GMAIL,
                new MockCredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_true(
            new AccountInformation(
                "test",
                ServiceProvider.OUTLOOK,
                new MockCredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_true(
            new AccountInformation(
                "test",
                ServiceProvider.YAHOO,
                new MockCredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
    }

    public void test_sender_mailboxes() throws GLib.Error {
        AccountInformation test = new AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new MockCredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );

        assert_true(test.primary_mailbox.equal_to(
                        new RFC822.MailboxAddress(null, "test1@example.com")));
        assert_false(test.has_sender_aliases);

        test.append_sender(new RFC822.MailboxAddress(null, "test2@example.com"));
        assert_true(test.has_sender_aliases);

        test.append_sender(new RFC822.MailboxAddress(null, "test3@example.com"));
        assert_true(test.has_sender_aliases);

        assert_true(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "test1@example.com")),
            "Primary address not found"
        );
        assert_true(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "test2@example.com")),
            "First alt address not found"
        );
        assert_true(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "test3@example.com")),
            "Second alt address not found"
        );
        assert_false(
            test.has_sender_mailbox(new RFC822.MailboxAddress(null, "unknowne@example.com")),
            "Unknown address found"
        );
    }

}
