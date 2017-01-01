/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _BUILD_ROOT_DIR;

public abstract class ClientWebViewTestCase<V> : Gee.TestCase {

    protected V test_view = null;

    public ClientWebViewTestCase(string name) {
        base(name);
    }

    public override void set_up() {
        ClientWebView.init_web_context(File.new_for_path(_BUILD_ROOT_DIR).get_child("src"), true);
        try {
            ClientWebView.load_scripts();
        } catch (Error err) {
            assert_not_reached();
        }
        this.test_view = set_up_test_view();
    }

    protected abstract V set_up_test_view();

    protected virtual void load_body_fixture(string? html = null) {
        ClientWebView client_view = (ClientWebView) this.test_view;
        client_view.load_html(html);
        while (client_view.is_loading) {
            Gtk.main_iteration();
        }
    }

}
