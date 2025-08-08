/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


public abstract class Components.WebViewTestCase<V> : TestCase {

    protected V? test_view = null;
    protected Application.Configuration? config = null;

    protected WebViewTestCase(string name) {
        base(name);
    }

    public override void set_up() {
        this.config = new Application.Configuration(Application.Client.SCHEMA_ID);
        this.config.enable_debug = true;

        WebView.init_web_context(
            this.config,
            File.new_for_path(Config.BUILD_ROOT_DIR).get_child("src")
        );
        try {
            WebView.load_resources(GLib.File.new_for_path("/tmp"));
        } catch (GLib.Error err) {
            GLib.assert_not_reached();
        }

        this.test_view = set_up_test_view(
            File.new_for_path("/tmp") // XXX use something better here
        );
    }

    protected override void tear_down() {
        this.config = null;
        this.test_view = null;
    }

    protected abstract V set_up_test_view(GLib.File cache_dir);

    protected virtual void load_body_fixture(string html = "") {
        WebView client_view = (WebView) this.test_view;
        client_view.load_html_headless(html);

        unowned GLib.MainContext? main_context = GLib.MainContext.get_thread_default();
        while (!client_view.is_content_loaded) {
            main_context.iteration(true);
        }
    }

    protected JSC.Value? run_javascript(string command) throws Error {
        WebView view = (WebView) this.test_view;
        view.evaluate_javascript.begin(command, -1, null, null, null, this.async_completion);
        return view.evaluate_javascript.end(async_result());
    }

}
