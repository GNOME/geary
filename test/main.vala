/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

int main(string[] args) {
    /*
     * Initialise all the things.
     */

    Test.init(ref args);

    Geary.RFC822.init();
    Geary.HTML.init();

    /*
     * Hook up all tests into appropriate suites
     */

    TestSuite engine = new TestSuite("engine");

    engine.add_suite(new Geary.HTML.UtilTest().get_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageDataTest().get_suite());
    engine.add_suite(new Geary.RFC822.Utils.Test().get_suite());

    TestSuite client = new TestSuite("client");

    /*
     * Run the tests
     */
    TestSuite root = TestSuite.get_root();
    root.add_suite(engine);
    root.add_suite(client);

    return Test.run();
}
