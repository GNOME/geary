/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Components.PageStateTest : WebViewTestCase<WebView> {


    private class TestWebView : Components.WebView {

        public TestWebView(Application.Configuration config) {
            base(config);
        }

        public new async void call_void(Util.JS.Callable callable)
            throws GLib.Error {
            yield base.call_void(callable, null);
        }

        public new async string call_returning(Util.JS.Callable callable)
            throws GLib.Error {
            return yield base.call_returning<string>(callable, null);
        }

    }


    public PageStateTest() {
        base("Components.PageStateTest");
        add_test("content_loaded", content_loaded);
        add_test("call_void", call_void);
        add_test("call_returning", call_returning);

        try {
            WebView.load_resources(GLib.File.new_for_path("/tmp"));
        } catch (GLib.Error err) {
            GLib.assert_not_reached();
        }

    }

    public void content_loaded() throws Error {
        bool content_loaded_triggered = false;
        this.test_view.content_loaded.connect(() => {
                content_loaded_triggered = true;
            });

        assert(!this.test_view.is_content_loaded);

        // XXX sketchy - this call will never return if the thing we
        // are testing does not work
        load_body_fixture("OHHAI");

        assert(this.test_view.is_content_loaded);
        assert(content_loaded_triggered);
    }

    public void call_void() throws GLib.Error {
        load_body_fixture("OHHAI");
        var test_article = this.test_view as TestWebView;

        test_article.call_void.begin(
            new Util.JS.Callable("testVoid"), this.async_completion
        );
        test_article.call_void.end(this.async_result());
        assert_test_result("void");
    }

    public void call_returning() throws GLib.Error {
        load_body_fixture("OHHAI");
        var test_article = this.test_view as TestWebView;

        test_article.call_returning.begin(
            new Util.JS.Callable("testReturn").string("check 1-2"),
            this.async_completion
        );
        string ret = test_article.call_returning.end(this.async_result());
        assert_equal(ret, "check 1-2");
        assert_test_result("check 1-2");
    }

    protected override WebView set_up_test_view() {
        WebKit.UserScript test_script;
        test_script = new WebKit.UserScript(
            "var geary = new PageState()",
            WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserScriptInjectionTime.START,
            null,
            null
        );

        WebView view = new TestWebView(this.config);
        view.get_user_content_manager().add_script(test_script);
        return view;
    }

    private void assert_test_result(string expected)
        throws GLib.Error {
        string? result = Util.JS.to_string(
            run_javascript("geary.testResult")
            .get_js_value()
        );
        assert_equal(result, expected);
    }

}
