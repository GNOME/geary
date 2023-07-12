/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class ConversationPageStateTest : Components.WebViewTestCase<ConversationWebView> {

    public ConversationPageStateTest() {
        base("ConversationPageStateTest");
        add_test("is_deceptive_text_not_url", is_deceptive_text_not_url);
        add_test("is_deceptive_text_identical_text", is_deceptive_text_identical_text);
        add_test("is_deceptive_text_matching_url", is_deceptive_text_matching_url);
        add_test("is_deceptive_text_common_href_subdomain", is_deceptive_text_common_href_subdomain);
        add_test("is_deceptive_text_common_text_subdomain", is_deceptive_text_common_text_subdomain);
        add_test("is_deceptive_text_deceptive_href", is_deceptive_text_deceptive_href);
        add_test("is_deceptive_text_non_matching_subdomain", is_deceptive_text_non_matching_subdomain);
        add_test("is_deceptive_text_different_domain", is_deceptive_text_different_domain);
        add_test("is_deceptive_text_embedded_domain", is_deceptive_text_embedded_domain);
        add_test("is_deceptive_text_innocuous", is_deceptive_text_innocuous);
        add_test("is_deceptive_text_gitlab", is_deceptive_text_gitlab);
        add_test("is_descendant_of", is_descendant_of);
        add_test("is_descendant_of_with_class", is_descendant_of_with_class);
        add_test("is_descendant_of_no_match", is_descendant_of_no_match);
        add_test("is_descendant_of_lax", is_descendant_of_lax);

        try {
            ConversationWebView.load_resources();
        } catch (GLib.Error err) {
            GLib.assert_not_reached();
        }
    }

    public void is_deceptive_text_not_url() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("ohhai!", "http://example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_identical_text() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("http://example.com", "http://example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_matching_url() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("example.com", "http://example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_common_href_subdomain() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("example.com", "http://foo.example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_common_text_subdomain() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("www.example.com", "http://example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_deceptive_href() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("www.example.com", "ohhai!") ==
               ConversationWebView.DeceptiveText.DECEPTIVE_HREF);
    }

    public void is_deceptive_text_non_matching_subdomain() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("www.example.com", "phishing.com") ==
               ConversationWebView.DeceptiveText.DECEPTIVE_DOMAIN);
    }

    public void is_deceptive_text_different_domain() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("www.example.com", "phishing.net") ==
               ConversationWebView.DeceptiveText.DECEPTIVE_DOMAIN);
    }

    public void is_deceptive_text_embedded_domain() throws GLib.Error {
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("Check out why phishing.net is bad!", "example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_innocuous() throws GLib.Error {
        // https://gitlab.gnome.org/GNOME/geary/issues/400
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("This will be fixed in the next freedesktop-sdk release (18.08.30)", "example.com") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_deceptive_text_gitlab() throws GLib.Error {
        // Link text in gitlab is "@user.name", which was previously false positive (@ can't be part of a domain)
        load_body_fixture("<p>my hovercraft is full of eels</p>");
        assert(exec_is_deceptive_text("@user.name", "http://gitlab.org/user.name") ==
               ConversationWebView.DeceptiveText.NOT_DECEPTIVE);
    }

    public void is_descendant_of() throws GLib.Error {
        load_body_fixture("<blockquote><div id='test'>ohhai</div></blockquote>");
        assert(
            Util.JS.to_bool(
                run_javascript("""
                    ConversationPageState.isDescendantOf(
                        document.getElementById('test'), "BLOCKQUOTE"
                    );
                """)
           )
        );
    }

    public void is_descendant_of_with_class() throws GLib.Error {
        load_body_fixture("<blockquote class='test-class'><div id='test'>ohhai</div></blockquote>");
        assert(
            Util.JS.to_bool(
                run_javascript("""
                    ConversationPageState.isDescendantOf(
                        document.getElementById('test'), "BLOCKQUOTE", "test-class"
                    );
                """)
           )
        );
    }

    public void is_descendant_of_no_match() throws GLib.Error {
        load_body_fixture("<blockquote class='test-class'><div id='test'>ohhai</div></blockquote>");
        assert(
            Util.JS.to_bool(
                run_javascript("""
                    ConversationPageState.isDescendantOf(
                        document.getElementById('test'), "DIV"
                    );
                """)
           )
        );
    }

    public void is_descendant_of_lax() throws GLib.Error {
        load_body_fixture("<blockquote class='test-class'><div id='test'>ohhai</div></blockquote>");
        assert(
            Util.JS.to_bool(
                run_javascript("""
                    ConversationPageState.isDescendantOf(
                        document.getElementById('test'), "DIV", null, false
                    );
                """)
           )
        );
    }


    protected override ConversationWebView set_up_test_view() {
        return new ConversationWebView(this.config);
    }

    private uint exec_is_deceptive_text(string text, string href)
        throws GLib.Error {
        uint ret = 0;
        try {
            ret = (uint) Util.JS.to_int32(
                run_javascript(@"ConversationPageState.isDeceptiveText(\"$text\", \"$href\")")
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
        return ret;
    }

}
