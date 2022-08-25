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
        add_test("test_service_label", test_service_label);
        add_test("folder_steps_accessors", folder_steps_accessors);
    }

    public void test_save_sent_defaults() throws GLib.Error {
        assert_true(
            new AccountInformation(
                "test",
                ServiceProvider.OTHER,
                new Mock.CredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_false(
            new AccountInformation(
                "test",
                ServiceProvider.GMAIL,
                new Mock.CredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
        assert_false(
            new AccountInformation(
                "test",
                ServiceProvider.OUTLOOK,
                new Mock.CredentialsMediator(),
                new RFC822.MailboxAddress(null, "test1@example.com")
            ).save_sent
        );
    }

    public void test_sender_mailboxes() throws GLib.Error {
        AccountInformation test = new AccountInformation(
            "test",
            ServiceProvider.OTHER,
            new Mock.CredentialsMediator(),
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

    public void test_service_label() throws GLib.Error {
        AccountInformation test = new_information();
        assert_equal(test.service_label, "");

        test = new_information();
        test.incoming.host = "example.com";
        assert_equal(test.service_label, "example.com");

        test = new_information();
        test.incoming.host = "test.example.com";
        assert_equal(test.service_label, "example.com");

        test = new_information();
        test.incoming.host = "other.com";
        test.outgoing.host = "other.com";
        assert_equal(test.service_label, "other.com");

        test = new_information();
        test.incoming.host = "mail.other.com";
        test.outgoing.host = "mail.other.com";
        assert_equal(test.service_label, "other.com");

        test = new_information();
        test.incoming.host = "imap.other.com";
        test.outgoing.host = "smtp.other.com";
        assert_equal(test.service_label, "other.com");

        test = new_information();
        test.incoming.host = "not-mail.other.com";
        test.outgoing.host = "not-mail.other.com";
        assert_equal(test.service_label, "other.com");
    }

    public void folder_steps_accessors() throws GLib.Error {
        AccountInformation test = new_information();

        assert_collection(test.get_folder_steps_for_use(NONE)).is_empty();
        assert_collection(test.get_folder_steps_for_use(ARCHIVE)).is_empty();
        assert_collection(test.get_folder_steps_for_use(JUNK)).is_empty();

        var archive = new Gee.ArrayList<string>.wrap({"Archive"});
        test.set_folder_steps_for_use(ARCHIVE, archive);
        assert_collection(test.get_folder_steps_for_use(ARCHIVE))
        .is_non_empty()
        .contains("Archive");

        var junk = new Gee.ArrayList<string>.wrap({"Junk"});
        test.set_folder_steps_for_use(JUNK, junk);
        assert_collection(test.get_folder_steps_for_use(ARCHIVE))
        .is_non_empty()
        .contains("Archive");
        assert_collection(test.get_folder_steps_for_use(JUNK))
        .is_non_empty()
        .contains("Junk");
    }

    private AccountInformation new_information(ServiceProvider provider =
                                               ServiceProvider.OTHER) {
        return new AccountInformation(
            "test",
            provider,
            new Mock.CredentialsMediator(),
            new RFC822.MailboxAddress(null, "test1@example.com")
        );
    }

}
