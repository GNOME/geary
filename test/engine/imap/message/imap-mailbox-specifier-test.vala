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

}
