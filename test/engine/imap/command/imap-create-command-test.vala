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
        assert(new CreateCommand(new MailboxSpecifier("owatagusiam/")).to_string() ==
               "---- create owatagusiam/");
    }

    public void special_use() throws Error {
        assert(new CreateCommand.special_use(
                   new MailboxSpecifier("Everything"),
                   SpecialFolderType.ALL_MAIL
                   ).to_string() == "---- create Everything (use (\\All))");
    }

}
