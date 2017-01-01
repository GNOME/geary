/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class ComposerPageStateTest : ClientWebViewTestCase<ComposerWebView> {

    public ComposerPageStateTest() {
        base("ComposerPageStateTest");
        add_test("get_html", get_html);
        add_test("get_text", get_text);
        add_test("get_text_with_quote", get_text_with_quote);
        add_test("get_text_with_nested_quote", get_text_with_nested_quote);
        add_test("resolve_nesting", resolve_nesting);
        add_test("quote_lines", quote_lines);
        add_test("replace_non_breaking_space", replace_non_breaking_space);
    }

    public void get_html() {
        string html = "<p>para</p>";
        load_body_fixture(html);
        try {
            assert(run_javascript(@"window.geary.getHtml();") == html + "<br><br>");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void get_text() {
        load_body_fixture("<p>para</p>");
        try {
            assert(run_javascript(@"window.geary.getText();") == "para\n\n\n\n");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_quote() {
        unichar q_marker = Geary.RFC822.Utils.QUOTE_MARKER;
        load_body_fixture("<p>pre</p> <blockquote><p>quote</p></blockquote> <p>post</p>");
        try {
            assert(run_javascript(@"window.geary.getText();") ==
                   @"pre\n\n$(q_marker)quote\n$(q_marker)\npost\n\n\n\n");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_nested_quote() {
        unichar q_marker = Geary.RFC822.Utils.QUOTE_MARKER;
        load_body_fixture("<p>pre</p> <blockquote><p>quote1</p> <blockquote><p>quote2</p></blockquote></blockquote> <p>post</p>");
        try {
            assert(run_javascript(@"window.geary.getText();") ==
                   @"pre\n\n$(q_marker)quote1\n$(q_marker)\n$(q_marker)$(q_marker)quote2\n$(q_marker)$(q_marker)\npost\n\n\n\n");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void resolve_nesting() {
        load_body_fixture();
        unichar q_marker = Geary.RFC822.Utils.QUOTE_MARKER;
        unichar q_start = '';
        unichar q_end = '';
        string js_no_quote = "foo";
        string js_spaced_quote = @"foo $(q_start)0$(q_end) bar";
        string js_leading_quote = @"$(q_start)0$(q_end) bar";
        string js_hanging_quote = @"foo $(q_start)0$(q_end)";
        string js_cosy_quote1 = @"foo$(q_start)0$(q_end)bar";
        string js_cosy_quote2 = @"foo$(q_start)0$(q_end)$(q_start)1$(q_end)bar";
        string js_values = "['quote1','quote2']";
        try {
            assert(run_javascript(@"ComposerPageState.resolveNesting('$(js_no_quote)', $(js_values));") ==
                   @"foo");
            assert(run_javascript(@"ComposerPageState.resolveNesting('$(js_spaced_quote)', $(js_values));") ==
                   @"foo \n$(q_marker)quote1\n bar");
            assert(run_javascript(@"ComposerPageState.resolveNesting('$(js_leading_quote)', $(js_values));") ==
                   @"$(q_marker)quote1\n bar");
            assert(run_javascript(@"ComposerPageState.resolveNesting('$(js_hanging_quote)', $(js_values));") ==
                   @"foo \n$(q_marker)quote1");
            assert(run_javascript(@"ComposerPageState.resolveNesting('$(js_cosy_quote1)', $(js_values));") ==
                   @"foo\n$(q_marker)quote1\nbar");
            assert(run_javascript(@"ComposerPageState.resolveNesting('$(js_cosy_quote2)', $(js_values));") ==
                   @"foo\n$(q_marker)quote1\n$(q_marker)quote2\nbar");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void quote_lines() {
        load_body_fixture();
        unichar q_marker = Geary.RFC822.Utils.QUOTE_MARKER;
        try {
            assert(run_javascript("ComposerPageState.quoteLines('');") ==
                   @"$(q_marker)");
            assert(run_javascript("ComposerPageState.quoteLines('line1');") ==
                   @"$(q_marker)line1");
            assert(run_javascript("ComposerPageState.quoteLines('line1\\nline2');") ==
                   @"$(q_marker)line1\n$(q_marker)line2");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void replace_non_breaking_space() {
        load_body_fixture();
        string single_nbsp = "a b";
        string multiple_nbsp = "a b c";
        try {
            assert(run_javascript(@"ComposerPageState.replaceNonBreakingSpace('$(single_nbsp)');") ==
                   "a b");
            assert(run_javascript(@"ComposerPageState.replaceNonBreakingSpace('$(multiple_nbsp)');") ==
                   "a b c");
        } catch (Geary.JS.Error err) {
            print("Geary.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    protected override ComposerWebView set_up_test_view() {
        try {
            ComposerWebView.load_resources();
        } catch (Error err) {
            assert_not_reached();
        }
        Configuration config = new Configuration(GearyApplication.APP_ID);
        return new ComposerWebView(config);
    }

    protected override void load_body_fixture(string? html = null) {
        this.test_view.load_html(html, null, false);
        while (this.test_view.is_loading) {
            Gtk.main_iteration();
        }
    }

    protected string run_javascript(string command) throws Error {
        this.test_view.run_javascript.begin(
            command, null, (obj, res) => { async_complete(res); }
        );

        WebKit.JavascriptResult result =
           this.test_view.run_javascript.end(async_result());
        return WebKitUtil.to_string(result);
    }

}
