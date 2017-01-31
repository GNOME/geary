/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class ClientWebViewTest : Gee.TestCase {

    public ClientWebViewTest() {
        base("ClientWebViewTest");
        add_test("init_web_context", init_web_context);
        add_test("load_resources", load_resources);
    }

    public void init_web_context() {
        Configuration config = new Configuration(GearyApplication.APP_ID);
        ClientWebView.init_web_context(
            config,
            File.new_for_path(_BUILD_ROOT_DIR).get_child("src"),
            File.new_for_path("/tmp"), // XXX use something better here
            true
        );
    }

    public void load_resources() {
        try {
            ClientWebView.load_scripts();
        } catch (Error err) {
            assert_not_reached();
        }
    }

}
