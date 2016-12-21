/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

int main(string[] args) {
    Test.init(ref args);

    Geary.RFC822.init();
    Geary.HTML.init();

    TestSuite root = TestSuite.get_root();

    // Engine tests
    root.add_suite(new Geary.HTML.UtilTest().get_suite());
    root.add_suite(new Geary.RFC822.MailboxAddressTest().get_suite());
    root.add_suite(new Geary.RFC822.MessageTest().get_suite());
    root.add_suite(new Geary.RFC822.MessageDataTest().get_suite());
    root.add_suite(new Geary.RFC822.Utils.Test().get_suite());

    return Test.run();
}
