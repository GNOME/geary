/*
 * Copyright 2016-2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


int main(string[] args) {
    /*
     * Set env vars right up front to avoid weird bugs
     */

    // Use the memory GSettings DB so we a) always start with default
    // values, and b) don't persist any changes made during a test
    Environment.set_variable("GSETTINGS_BACKEND", "memory", true);

    // Let GSettings know where to find the dev schema
    Environment.set_variable("GSETTINGS_SCHEMA_DIR", Config.GSETTINGS_DIR, true);

    /*
     * Initialise all the things.
     */

    GLib.Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");

    Gtk.init();
    Test.init(ref args);

    Geary.RFC822.init();
    Geary.HTML.init();
    Geary.Logging.init();
    if (GLib.Test.verbose()) {
        GLib.Log.set_writer_func(Geary.Logging.default_log_writer);
        Geary.Logging.log_to(GLib.stdout);
    }

    /*
     * Hook up all tests into appropriate suites
     */

    TestSuite client = new TestSuite("client");

    // Keep this before other ClientWebView based tests since it tests
    // WebContext init
    client.add_suite(new Accounts.ManagerTest().steal_suite());
    client.add_suite(new Application.CertificateManagerTest().steal_suite());
    client.add_suite(new Application.ClientTest().steal_suite());
    client.add_suite(new Application.ConfigurationTest().steal_suite());
    client.add_suite(new Components.WebViewTest().steal_suite());
    client.add_suite(new Components.ValidatorTest().steal_suite());
    client.add_suite(new Composer.WebViewTest().steal_suite());
    client.add_suite(new Composer.WidgetTest().steal_suite());
    client.add_suite(new Util.Cache.Test().steal_suite());
    client.add_suite(new Util.Email.Test().steal_suite());
    client.add_suite(new Util.JS.Test().steal_suite());

    /*
     * Run the tests
     */
    unowned TestSuite root = TestSuite.get_root();
    root.add_suite((owned) client);

    MainLoop loop = new MainLoop();

    int ret = -1;
    Idle.add(() => {
        ret = Test.run();
        loop.quit();
        return Source.REMOVE;
    });

    loop.run();
    return ret;
}
