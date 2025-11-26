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
    Environment.set_variable("GSETTINGS_SCHEMA_DIR", _GSETTINGS_DIR, true);

    /*
     * Initialise all the things.
     */

    GLib.Intl.setlocale(LocaleCategory.ALL, "C.UTF-8");

    Gtk.init(ref args);
    Test.init(ref args);

    IconFactory.init(GLib.File.new_for_path(_SOURCE_ROOT_DIR));
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
    client.add_suite(new Accounts.ManagerTest().suite);
    client.add_suite(new Application.CertificateManagerTest().suite);
    client.add_suite(new Application.ClientTest().suite);
    client.add_suite(new Application.ConfigurationTest().suite);
    client.add_suite(new Components.WebViewTest().suite);
    client.add_suite(new Components.ValidatorTest().suite);
    client.add_suite(new Composer.WebViewTest().suite);
    client.add_suite(new Composer.WidgetTest().suite);
    client.add_suite(new Util.Cache.Test().suite);
    client.add_suite(new Util.Email.Test().suite);
    client.add_suite(new Util.JS.Test().suite);

    /*
     * Run the tests
     */
    TestSuite root = TestSuite.get_root();
    root.add_suite(client);

    int ret = -1;
    Idle.add(() => {
            ret = Test.run();
            Gtk.main_quit();
            return false;
        });

    Gtk.main();
    return ret;
}
