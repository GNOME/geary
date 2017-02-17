/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _GSETTINGS_DIR;

int main(string[] args) {
    /*
     * Set env vars right up front to avoid weird bugs
     */

    // Use the memory GSettings DB so we a) always start with default
    // values, and b) don't persist any changes made during a test
    Environment.set_variable("GSETTINGS_BACKEND", "memory", true);

    // Let GSettings know where to find the dev schema
    Environment.set_variable("GSETTINGS_SCHEMA_DIR", _GSETTINGS_DIR, true);

    /*
     * Initialise all the things.
     */

    Gtk.init(ref args);
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
    engine.add_suite(new Geary.HTML.UtilTest().get_suite());
    engine.add_suite(new Geary.IdleManagerTest().get_suite());
    engine.add_suite(new Geary.Inet.Test().get_suite());
    engine.add_suite(new Geary.JS.Test().get_suite());
    engine.add_suite(new Geary.Mime.ContentTypeTest().get_suite());
    engine.add_suite(new Geary.RFC822.MailboxAddressTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageTest().get_suite());
    engine.add_suite(new Geary.RFC822.MessageDataTest().get_suite());
    engine.add_suite(new Geary.RFC822.Utils.Test().get_suite());
    engine.add_suite(new Geary.TimeoutManagerTest().get_suite());

    TestSuite client = new TestSuite("client");

    // Keep this before other ClientWebView based tests since it tests
    // WebContext init
    client.add_suite(new ClientWebViewTest().get_suite());

    client.add_suite(new ComposerWebViewTest().get_suite());
    client.add_suite(new ConfigurationTest().get_suite());

    TestSuite js = new TestSuite("js");

    js.add_suite(new ComposerPageStateTest().get_suite());
    js.add_suite(new ConversationPageStateTest().get_suite());

    /*
     * Run the tests
     */
    TestSuite root = TestSuite.get_root();
    root.add_suite(engine);
    root.add_suite(client);
    root.add_suite(js);

    int ret = -1;
    Idle.add(() => {
            ret = Test.run();
            Gtk.main_quit();
            return false;
        });

    Gtk.main();
    return ret;
}
