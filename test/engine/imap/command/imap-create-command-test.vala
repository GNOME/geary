/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.CreateCommandTest : Gee.TestCase {


    public CreateCommandTest() {
        base("Geary.Imap.CreateCommandTest");
        add_test("test_basic_create", test_basic_create);
        add_test("test_special_use", test_special_use);
    }

    public void test_basic_create() {
        assert(new CreateCommand(new MailboxSpecifier("owatagusiam/")).to_string() ==
               "---- create owatagusiam/");
    }

    public void test_special_use() {
        assert(new CreateCommand.special_use(
                   new MailboxSpecifier("Everything"),
                   SpecialFolderType.ALL_MAIL
                   ).to_string() == "---- create Everything (use (\\All))");
    }

}
