/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.MailboxSpecifierTest : TestCase {


    public MailboxSpecifierTest() {
        base("Geary.Imap.MailboxSpecifierTest");
        add_test("to_parameter", to_parameter);
        add_test("from_parameter", from_parameter);
        add_test("from_folder_path", from_folder_path);
    }

    public void to_parameter() throws Error {
        assert_string(
            "test",
            new MailboxSpecifier("test").to_parameter().to_string()
        );
        assert_string(
            "foo/bar",
            new MailboxSpecifier("foo/bar").to_parameter().to_string()
        );

        // The param won't be quoted or escaped since
        // QuotedStringParameter doesn't actually handle that, so just
        // check that it is correct type
        Parameter quoted = new MailboxSpecifier("""foo\bar""").to_parameter();
        assert_true(quoted is QuotedStringParameter, "Backslash was not quoted");

        assert_string(
            "ol&AOk-",
            new MailboxSpecifier("olé").to_parameter().to_string()
        );
    }

    public void from_parameter() throws Error {
        assert_string(
            "test",
            new MailboxSpecifier.from_parameter(
                new UnquotedStringParameter("test")).name
        );

        // This won't be quoted or escaped since QuotedStringParameter
        // doesn't actually handle that.
        assert_string(
            "foo\\bar",
            new MailboxSpecifier.from_parameter(
                new QuotedStringParameter("""foo\bar""")).name
        );
        assert_string(
            "olé",
            new MailboxSpecifier.from_parameter(
                new UnquotedStringParameter("ol&AOk-")).name
        );
    }

    public void from_folder_path() throws Error {
        MockFolderRoot empty_root = new MockFolderRoot("");
        MailboxSpecifier empty_inbox = new MailboxSpecifier("Inbox");
        assert_string(
            "Foo",
            new MailboxSpecifier.from_folder_path(
                empty_root.get_child("Foo"), empty_inbox, "$"
            ).name
        );
        assert_string(
            "Foo$Bar",
            new MailboxSpecifier.from_folder_path(
                empty_root.get_child("Foo").get_child("Bar"), empty_inbox, "$"
            ).name
        );
        assert_string(
            "Inbox",
            new MailboxSpecifier.from_folder_path(
                empty_root.get_child(MailboxSpecifier.CANONICAL_INBOX_NAME),
                empty_inbox,
                "$"
            ).name
        );

        MockFolderRoot non_empty_root = new MockFolderRoot("Root");
        MailboxSpecifier non_empty_inbox = new MailboxSpecifier("Inbox");
        assert_string(
            "Root$Foo",
            new MailboxSpecifier.from_folder_path(
                non_empty_root.get_child("Foo"),
                non_empty_inbox,
                "$"
            ).name
        );
        assert_string(
            "Root$Foo$Bar",
            new MailboxSpecifier.from_folder_path(
                non_empty_root.get_child("Foo").get_child("Bar"),
                non_empty_inbox,
                "$"
            ).name
        );
        assert_string(
            "Root$INBOX",
            new MailboxSpecifier.from_folder_path(
                non_empty_root.get_child(MailboxSpecifier.CANONICAL_INBOX_NAME),
                non_empty_inbox,
                "$"
            ).name
        );
    }

}
