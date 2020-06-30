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
        add_test("folder_path_is_inbox", folder_path_is_inbox);
    }

    public void to_parameter() throws Error {
        assert_equal(
            new MailboxSpecifier("test").to_parameter().to_string(),
            "test"
        );
        assert_equal(
            new MailboxSpecifier("foo/bar").to_parameter().to_string(),
            "foo/bar"
        );

        // The param won't be quoted or escaped since
        // QuotedStringParameter doesn't actually handle that, so just
        // check that it is correct type
        Parameter quoted = new MailboxSpecifier("""foo\bar""").to_parameter();
        assert_true(quoted is QuotedStringParameter, "Backslash was not quoted");

        assert_equal(
            new MailboxSpecifier("olé").to_parameter().to_string(),
            "ol&AOk-"
        );
    }

    public void from_parameter() throws Error {
        assert_equal(
            new MailboxSpecifier.from_parameter(
                new UnquotedStringParameter("test")
            ).name,
            "test"
        );

        // This won't be quoted or escaped since QuotedStringParameter
        // doesn't actually handle that.
        assert_equal(
            new MailboxSpecifier.from_parameter(
                new QuotedStringParameter("""foo\bar""")
            ).name,
            "foo\\bar"
        );
        assert_equal(
            new MailboxSpecifier.from_parameter(
                new UnquotedStringParameter("ol&AOk-")
            ).name,
            "olé"
        );
    }

    public void from_folder_path() throws Error {
        FolderRoot root = new FolderRoot("#test");
        MailboxSpecifier inbox = new MailboxSpecifier("Inbox");
        assert_equal(
            new MailboxSpecifier.from_folder_path(
                root.get_child("Foo"), inbox, "$"
            ).name,
            "Foo"
        );
        assert_equal(
            new MailboxSpecifier.from_folder_path(
                root.get_child("Foo").get_child("Bar"), inbox, "$"
            ).name,
            "Foo$Bar"
        );
        assert_equal(
            new MailboxSpecifier.from_folder_path(
                root.get_child(MailboxSpecifier.CANONICAL_INBOX_NAME),
                inbox,
                "$"
            ).name,
            "Inbox"
        );

        try {
            new MailboxSpecifier.from_folder_path(
                root.get_child(""), inbox, "$"
            );
            assert_not_reached();
        } catch (GLib.Error err) {
            // all good
        }

        try {
            new MailboxSpecifier.from_folder_path(
                root.get_child("test").get_child(""), inbox, "$"
            );
            assert_not_reached();
        } catch (GLib.Error err) {
            // all good
        }

        try {
            new MailboxSpecifier.from_folder_path(root, inbox, "$");
            assert_not_reached();
        } catch (GLib.Error err) {
            // all good
        }
    }

    public void folder_path_is_inbox() throws GLib.Error {
        FolderRoot root = new FolderRoot("#test");
        assert_true(
            MailboxSpecifier.folder_path_is_inbox(root.get_child("Inbox"))
        );
        assert_true(
            MailboxSpecifier.folder_path_is_inbox(root.get_child("inbox"))
        );
        assert_true(
            MailboxSpecifier.folder_path_is_inbox(root.get_child("INBOX"))
        );

        assert_false(
            MailboxSpecifier.folder_path_is_inbox(root)
        );
        assert_false(
            MailboxSpecifier.folder_path_is_inbox(root.get_child("blah"))
        );
        assert_false(
            MailboxSpecifier.folder_path_is_inbox(
                root.get_child("blah").get_child("Inbox")
            )
        );
        assert_false(
            MailboxSpecifier.folder_path_is_inbox(
                root.get_child("Inbox").get_child("Inbox")
            )
        );
    }

}
