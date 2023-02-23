/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Components.WebViewTest : TestCase {

    public WebViewTest() {
        base("Components.WebViewTest");
        add_test("init_web_context", init_web_context);
        add_test("load_resources", load_resources);
    }

    public void init_web_context() throws Error {
        Application.Configuration config = new Application.Configuration(
            Application.Client.SCHEMA_ID
        );
        config.enable_debug = true;
        WebView.init_web_context(
            config,
            File.new_for_path(_BUILD_ROOT_DIR).get_child("src"),
            File.new_for_path("/tmp"), // XXX use something better here
            false // https://bugs.webkit.org/show_bug.cgi?id=213174
        );
    }

    public void load_resources() throws GLib.Error {
        try {
            WebView.load_resources(GLib.File.new_for_path("/tmp"));
        } catch (GLib.Error err) {
            assert_not_reached();
        }
    }

}
