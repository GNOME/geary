/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


public abstract class ClientWebViewTestCase<V> : TestCase {

    protected V? test_view = null;
    protected Configuration? config = null;

    protected ClientWebViewTestCase(string name) {
        base(name);
        this.config = new Configuration(GearyApplication.SCHEMA_ID);
        this.config.enable_debug = true;
        ClientWebView.init_web_context(
            this.config,
            File.new_for_path(_BUILD_ROOT_DIR).get_child("src"),
            File.new_for_path("/tmp") // XXX use something better here
        );
        try {
            ClientWebView.load_resources(GLib.File.new_for_path("/tmp"));
        } catch (GLib.Error err) {
            assert_not_reached();
        }
    }

    public override void set_up() {
        this.test_view = set_up_test_view();
    }

    protected abstract V set_up_test_view();

    protected virtual void load_body_fixture(string html = "") {
        ClientWebView client_view = (ClientWebView) this.test_view;
        client_view.load_html(html);
        while (!client_view.is_content_loaded) {
            Gtk.main_iteration();
        }
    }

    protected WebKit.JavascriptResult run_javascript(string command) throws Error {
        ClientWebView view = (ClientWebView) this.test_view;
        view.run_javascript.begin(
            command, null, (obj, res) => { async_complete(res); }
        );

        return view.run_javascript.end(async_result());
    }

}
