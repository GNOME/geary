/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.CreateCommandTest : TestCase {


    public CreateCommandTest() {
        base("Geary.Imap.CreateCommandTest");
        add_test("basic_create", basic_create);
        add_test("special_use", special_use);
    }

    public void basic_create() throws Error {
        assert_string(
            "---- create owatagusiam/",
            new CreateCommand(new MailboxSpecifier("owatagusiam/")).to_string()
        );
    }

    public void special_use() throws Error {
        assert_string(
            "---- create Everything (use (\\All))",
            new CreateCommand.special_use(
                new MailboxSpecifier("Everything"),
                ALL_MAIL
            ).to_string()
        );
    }

}
