/*
 * Copyright 2016-2017 Michael Gratton <mike@vee.net>
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
    Geary.Logging.init();

    /*
     * Hook up all tests into appropriate suites
     */

    TestSuite engine = new TestSuite("engine");

    engine.add_suite(new Geary.AttachmentTest().get_suite());
    engine.add_suite(new Geary.EngineTest().get_suite());
    engine.add_suite(new Geary.IdleManagerTest().get_suite());
    engine.add_suite(new Geary.TimeoutManagerTest().get_suite());
    engine.add_suite(new Geary.App.ConversationTest().get_suite());
    engine.add_suite(new Geary.App.ConversationSetTest().get_suite());
    engine.add_suite(new Geary.HTML.UtilTest().get_suite());
    engine.add_suite(new Geary.Imap.DeserializerTest().get_suite());
    engine.add_suite(new Geary.Imap.CreateCommandTest().get_suite());
    engine.add_suite(new Geary.Imap.NamespaceResponseTest().get_suite());
    engine.add_suite(new Geary.Inet.Test().get_suite());
    engine.add_suite(new Geary.JS.Test().get_suite());
    engine.add_suite(new Geary.Mime.ContentTypeTest().get_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageDataTest().get_suite());
    engine.add_suite(new Geary.RFC822.Utils.Test().get_suite());

    /*
     * Run the tests
     */
    TestSuite root = TestSuite.get_root();
    root.add_suite(engine);

    MainLoop loop = new MainLoop ();

    int ret = -1;
    Idle.add(() => {
            ret = Test.run();
            loop.quit();
            return false;
        });

    loop.run();
    return ret;
}
