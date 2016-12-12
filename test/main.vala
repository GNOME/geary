/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

int main(string[] args) {
    Test.init(ref args);
    TestSuite root = TestSuite.get_root();

    root.add_suite(new Geary.RFC822.MailboxAddressTest().get_suite());

    return Test.run();
}
