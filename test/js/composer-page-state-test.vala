/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _BUILD_ROOT_DIR;

class ComposerPageStateTest : Gee.TestCase {

    private ComposerWebView test_view = null;
    private AsyncQueue<AsyncResult> async_results = new AsyncQueue<AsyncResult>();

    public ComposerPageStateTest() {
        base("ComposerPageStateTest");
        add_test("get_html", get_html);
        add_test("get_text", get_text);
        add_test("get_text_with_quote", get_text_with_quote);
        add_test("get_text_with_nested_quote", get_text_with_nested_quote);
        add_test("resolve_nesting", resolve_nesting);
        add_test("quote_lines", quote_lines);
    }

    public override void set_up() {
        ClientWebView.init_web_context(File.new_for_path(_BUILD_ROOT_DIR).get_child("src"), true);
        try {
            ClientWebView.load_scripts();
            ComposerWebView.load_resources();
        } catch (Error err) {
            print("\nComposerPageStateTest::set_up: %s\n", err.message);
            assert_not_reached();
        }
        Configuration config = new Configuration(GearyApplication.APP_ID);
        this.test_view = new ComposerWebView(config);
    }

    public void get_html() {
        string html = "<p>para</p>";
        load_body_fixture(html);
        try {
            assert(run_javascript(@"window.geary.getHtml();") == html + "<br><br>");
        } catch (JSError err) {
            print("JSError: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void get_text() {
        load_body_fixture("<p>para</p>");
        try {
            assert(run_javascript(@"window.geary.getText();") == "para\n\n\n\n\n");
        } catch (JSError err) {
            print("JSError: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_quote() {
        load_body_fixture("<p>pre</p> <blockquote><p>quote</p></blockquote> <p>post</p>");
        try {
            assert(run_javascript(@"window.geary.getText();") ==
                   "pre\n\n> quote\n> \npost\n\n\n\n\n");
        } catch (JSError err) {
            print("JSError: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_nested_quote() {
        load_body_fixture("<p>pre</p> <blockquote><p>quote1</p> <blockquote><p>quote2</p></blockquote></blockquote> <p>post</p>");
        try {
            assert(run_javascript(@"window.geary.getText();") ==
                   "pre\n\n> quote1\n> \n>> quote2\n>> \npost\n\n\n\n\n");
        } catch (JSError err) {
            print("JSError: %s", err.message);
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
        } catch (JSError err) {
            print("JSError: %s", err.message);
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
        } catch (JSError err) {
            print("JSError: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    protected void load_body_fixture(string? html = null) {
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
        return get_string_result(result);
    }

    protected void async_complete(AsyncResult result) {
        this.async_results.push(result);
    }

    protected AsyncResult async_result() {
        AsyncResult? result = null;
        while (result == null) {
            Gtk.main_iteration();
            result = this.async_results.try_pop();
        }
        return result;
    }

    protected static string? get_string_result(WebKit.JavascriptResult result)
        throws JSError {
        JS.GlobalContext context = result.get_global_context();
        JS.Value js_str_value = result.get_value();
        JS.Value? err = null;
        JS.String js_str = context.to_string_copy(js_str_value, out err);

        check_exception(context, err);
        return to_string_released(js_str);
    }

    protected static inline void check_exception(JS.Context exe, JS.Value? err_value)
        throws JSError {
        if (!is_null(exe, err_value)) {
            JS.Value? nested_err = null;
            JS.Type err_type = err_value.get_type(exe);
            JS.String err_str = exe.to_string_copy(err_value, out nested_err);

            if (!is_null(exe, nested_err)) {
                throw new JSError.EXCEPTION(
                    "Nested exception getting exception %s as a string",
                    err_type.to_string()
                );
            }

            throw new JSError.EXCEPTION(
                "JS exception thrown [%s]: %s"
                .printf(err_type.to_string(), to_string_released(err_str))
            );
        }
    }

    protected static inline bool is_null(JS.Context exe, JS.Value? js) {
        return (js == null || js.get_type(exe) == JS.Type.NULL);
    }

    protected static string to_string_released(JS.String js) {
        int len = js.get_maximum_utf8_cstring_size();
        string str = string.nfill(len, 0);
        js.get_utf8_cstring(str, len);
        js.release();
        return str;
    }

}
