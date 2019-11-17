/*
 * Copyright 2016-2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


extern const string _INSTALL_PREFIX;
extern const string _BUILD_ROOT_DIR;
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

    // Ensure things like e.g. GLib's formatting routines uses a
    // well-known UTF-8-based locale rather ASCII. Would like to use
    // C.UTF-8 here, but currently only Debian et al and Fedora ship
    // it, and as of Fedora 32 they disagree on collation order for
    // non-ASCII chars.
    GLib.Intl.setlocale(LocaleCategory.ALL, "en_US.UTF-8");

    Gtk.init(ref args);
    Test.init(ref args);

    Geary.RFC822.init();
    Geary.HTML.init();
    Geary.Logging.init();

    /*
     * Hook up all tests into appropriate suites
     */

    TestSuite client = new TestSuite("client");

    // Keep this before other ClientWebView based tests since it tests
    // WebContext init
    client.add_suite(new Accounts.ManagerTest().get_suite());
    client.add_suite(new Application.ConfigurationTest().get_suite());
    client.add_suite(new ClientWebViewTest().get_suite());
    client.add_suite(new Composer.WebViewTest().get_suite());
    client.add_suite(new GearyApplicationTest().get_suite());
    client.add_suite(new Util.Avatar.Test().get_suite());
    client.add_suite(new Util.Cache.Test().get_suite());
    client.add_suite(new Util.Email.Test().get_suite());
    client.add_suite(new Util.JS.Test().get_suite());

    TestSuite js = new TestSuite("js");

    js.add_suite(new ClientPageStateTest().get_suite());
    js.add_suite(new Composer.PageStateTest().get_suite());
    js.add_suite(new ConversationPageStateTest().get_suite());

    /*
     * Run the tests
     */
    TestSuite root = TestSuite.get_root();
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
