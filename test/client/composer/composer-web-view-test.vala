/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class ComposerWebViewTest : ClientWebViewTestCase<ComposerWebView> {

    private const string BODY_TEMPLATE = """<div id="geary-body" dir="auto">%s<div><br></div><div><br></div></div>""";

    public ComposerWebViewTest() {
        base("ComposerWebViewTest");
        add_test("load_resources", load_resources);
        add_test("edit_context", edit_context);
        add_test("get_html", get_html);
        add_test("get_text", get_text);
        add_test("get_text_with_quote", get_text_with_quote);
        add_test("get_text_with_nested_quote", get_text_with_nested_quote);
        add_test("get_text_with_long_line", get_text_with_long_line);
        add_test("get_text_with_long_quote", get_text_with_long_quote);
        add_test("get_text_with_nbsp", get_text_with_nbsp);
    }

    public void load_resources() {
        try {
            ComposerWebView.load_resources();
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void edit_context() {
        assert(!(new ComposerWebView.EditContext("0,,,").is_link));
        assert(new ComposerWebView.EditContext("1,,,").is_link);
        assert(new ComposerWebView.EditContext("1,url,,").link_url == "url");

        assert(new ComposerWebView.EditContext("0,,Helvetica,").font_family == "sans");
        assert(new ComposerWebView.EditContext("0,,Times New Roman,").font_family == "serif");
        assert(new ComposerWebView.EditContext("0,,Courier,").font_family == "monospace");

        assert(new ComposerWebView.EditContext("0,,,12").font_size == 12);
    }

    public void get_html() {
        string html = "<p>para</p>";
        load_body_fixture(html);
        this.test_view.get_html.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_html.end(async_result()) ==
                   BODY_TEMPLATE.printf(html));
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text() {
        load_body_fixture("<p>para</p>");
        this.test_view.get_text.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_text.end(async_result()) == "para\n\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_quote() {
        load_body_fixture("<p>pre</p> <blockquote><p>quote</p></blockquote> <p>post</p>");
        this.test_view.get_text.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "pre\n\n> quote\n> \npost\n\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_nested_quote() {
        load_body_fixture("<p>pre</p> <blockquote><p>quote1</p> <blockquote><p>quote2</p></blockquote></blockquote> <p>post</p>");
        this.test_view.get_text.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "pre\n\n> quote1\n> \n>> quote2\n>> \npost\n\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_long_line() {
        load_body_fixture("""
<p>A long, long, long, long, long, long para. Well, longer than MAX_BREAKABLE_LEN
at least. Really long, long, long, long, long long, long long, long long, long.</p>
""");
        this.test_view.get_text.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_text.end(async_result()) ==
"""A long, long, long, long, long, long para. Well, longer than 
MAX_BREAKABLE_LEN at least. Really long, long, long, long, long long, 
long long, long long, long.




""");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_long_quote() {
        load_body_fixture("""
<blockquote><p>A long, long, long, long, long, long line. Well, longer than MAX_BREAKABLE_LEN at least.</p></blockquote>

<p>A long, long, long, long, long, long para. Well, longer than MAX_BREAKABLE_LEN
at least. Really long, long, long, long, long long, long long, long long, long.</p>""");
        this.test_view.get_text.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_text.end(async_result()) ==
"""> A long, long, long, long, long, long line. Well, longer than 
> MAX_BREAKABLE_LEN at least.
> 
A long, long, long, long, long, long para. Well, longer than 
MAX_BREAKABLE_LEN at least. Really long, long, long, long, long long, 
long long, long long, long.




""");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_nbsp() {
        load_body_fixture("""On Sun, Jan 1, 2017 at 9:55 PM, Michael Gratton &lt;mike@vee.net&gt; wrote:<br>
<blockquote type="cite">long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,
</blockquote><br>long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long,&nbsp;<div style="white-space: pre;">
</div>

""");
        this.test_view.get_text.begin((obj, ret) => { async_complete(ret); });
        try {
            assert(this.test_view.get_text.end(async_result()) ==
"""On Sun, Jan 1, 2017 at 9:55 PM, Michael Gratton <mike@vee.net> wrote:
> long, long, long, long, long, long, long, long, long, long, long, 
> long, long, long, long, long, long, long, long, long, long, long, 
> long, long, long, long, long, long, long, long, long, long, long, 
> long, long, long, long, long, long, long, long, long, long, long, 
> long, long, long, long, long,

long, long, long, long, long, long, long, long, long, long, long, long, 
long, long, long, long, long, long, long, long, long, long, long, long, 
long, long, long, long, long, long, long, long, long, long, long, long, 
long, long, long, long, long, long, long, long, long, long, long, long, 
long, long, long, long, long, long, long, long, long, long,




""");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    protected override ComposerWebView set_up_test_view() {
        return new ComposerWebView(this.config);
    }

    protected override void load_body_fixture(string html = "") {
        this.test_view.load_html(html, "", "", false, false);
        while (this.test_view.is_loading) {
            Gtk.main_iteration();
        }
    }

}
