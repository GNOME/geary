/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class ClientPageStateTest : ClientWebViewTestCase<ClientWebView> {


    private class TestClientWebView : ClientWebView {

        public TestClientWebView(Configuration config) {
            base(config);
        }

    }


    public ClientPageStateTest() {
        base("ClientPageStateTest");
        add_test("content_loaded", content_loaded);

        try {
            ClientWebView.load_resources(GLib.File.new_for_path("/tmp"));
        } catch (GLib.Error err) {
            assert_not_reached();
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

    protected override ClientWebView set_up_test_view() {
        WebKit.UserScript test_script;
        test_script = new WebKit.UserScript(
            "var geary = new PageState()",
            WebKit.UserContentInjectedFrames.TOP_FRAME,
            WebKit.UserScriptInjectionTime.START,
            null,
            null
        );

        ClientWebView view = new TestClientWebView(this.config);
        view.get_user_content_manager().add_script(test_script);
        return view;
    }

}
