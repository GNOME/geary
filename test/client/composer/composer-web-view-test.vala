/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Composer.WebViewTest : Components.WebViewTestCase<Composer.WebView> {


    public WebViewTest() {
        base("Composer.WebViewTest");
        add_test("load_resources", load_resources);
        add_test("edit_context", edit_context);
        add_test("get_html", get_html);
        add_test("get_html_for_draft", get_html_for_draft);
        add_test("get_text", get_text);
        add_test("get_text_with_quote", get_text_with_quote);
        add_test("get_text_with_nested_quote", get_text_with_nested_quote);
        add_test("get_text_with_long_line", get_text_with_long_line);
        add_test("get_text_with_long_quote", get_text_with_long_quote);
        add_test("get_text_with_nbsp", get_text_with_nbsp);
        add_test("get_text_with_named_link", get_text_with_named_link);
        add_test("get_text_with_url_link", get_text_with_named_link);
        add_test("get_text_with_surrounding_nbsps", get_text_with_surrounding_nbsps);
        add_test("update_signature", update_signature);

        try {
            WebView.load_resources();
        } catch (Error err) {
            GLib.assert_not_reached();
        }
    }

    public void load_resources() throws Error {
        try {
            WebView.load_resources();
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void edit_context() throws Error {
        assert(!(new WebView.EditContext("0;;;;").is_link));
        assert(new WebView.EditContext("1;;;;").is_link);
        assert(new WebView.EditContext("1;url;;;").link_url == "url");

        assert(new WebView.EditContext("0;;Helvetica;;").font_family == "sans");
        assert(new WebView.EditContext("0;;Times New Roman;;").font_family == "serif");
        assert(new WebView.EditContext("0;;Courier;;").font_family == "monospace");

        assert(new WebView.EditContext("0;;;12;").font_size == 12);

        assert(new WebView.EditContext("0;;;;rgb(0, 0, 0)").font_color == Util.Gtk.rgba(0, 0, 0, 1));
        assert(new WebView.EditContext("0;;;;rgb(255, 0, 0)").font_color == Util.Gtk.rgba(1, 0, 0, 1));
        assert(new WebView.EditContext("0;;;;rgb(0, 255, 0)").font_color == Util.Gtk.rgba(0, 1, 0, 1));
        assert(new WebView.EditContext("0;;;;rgb(0, 0, 255)").font_color == Util.Gtk.rgba(0, 0, 1, 1));
    }

    public void get_html() throws GLib.Error {
        string BODY = "<p>para</p>";
        load_body_fixture(BODY);
        this.test_view.get_html.begin(this.async_completion);
        string html = this.test_view.get_html.end(async_result());
        assert_equal(html, PageStateTest.CLEAN_BODY_TEMPLATE.printf(BODY));
    }

    public void get_html_for_draft() throws GLib.Error {
        string BODY = "<p>para</p>";
        load_body_fixture(BODY);
        this.test_view.get_html_for_draft.begin(this.async_completion);
        string html = this.test_view.get_html.end(async_result());
        assert_equal(html, PageStateTest.COMPLETE_BODY_TEMPLATE.printf(BODY));
    }

    public void get_text() throws Error {
        load_body_fixture("<p>para</p>");
        this.test_view.get_text.begin(this.async_completion);
        try {
            assert(this.test_view.get_text.end(async_result()) == "para\n\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_quote() throws Error {
        load_body_fixture("<p>pre</p> <blockquote><p>quote</p></blockquote> <p>post</p>");
        this.test_view.get_text.begin(this.async_completion);
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "pre\n\n> quote\n> \npost\n\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_nested_quote() throws Error {
        load_body_fixture("<p>pre</p> <blockquote><p>quote1</p> <blockquote><p>quote2</p></blockquote></blockquote> <p>post</p>");
        this.test_view.get_text.begin(this.async_completion);
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "pre\n\n> quote1\n> \n>> quote2\n>> \npost\n\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_long_line() throws Error {
        load_body_fixture("""
<p>A long, long, long, long, long, long para. Well, longer than MAX_BREAKABLE_LEN
at least. Really long, long, long, long, long long, long long, long long, long.</p>
""");
        this.test_view.get_text.begin(this.async_completion);
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

    public void get_text_with_long_quote() throws Error {
        load_body_fixture("""
<blockquote><p>A long, long, long, long, long, long line. Well, longer than MAX_BREAKABLE_LEN at least.</p></blockquote>

<p>A long, long, long, long, long, long para. Well, longer than MAX_BREAKABLE_LEN
at least. Really long, long, long, long, long long, long long, long long, long.</p>""");
        this.test_view.get_text.begin(this.async_completion);
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

    public void get_text_with_nbsp() throws Error {
        load_body_fixture("""On Sun, Jan 1, 2017 at 9:55 PM, Michael Gratton &lt;mike@vee.net&gt; wrote:<br>
<blockquote type="cite">long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,&nbsp;long,
</blockquote><br>long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long, long,&nbsp;<div style="white-space: pre;">
</div>

""");
        this.test_view.get_text.begin(this.async_completion);
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

    public void get_text_with_named_link() throws Error {
        load_body_fixture("Check out <a href=\"https://wiki.gnome.org/Apps/Geary\">Geary</a>!");
        this.test_view.get_text.begin(this.async_completion);
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "Check out Geary <https://wiki.gnome.org/Apps/Geary>!\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_url_link() throws Error {
        load_body_fixture("Check out <a href=\"https://wiki.gnome.org/Apps/Geary\">https://wiki.gnome.org/Apps/Geary</a>!");
        this.test_view.get_text.begin(this.async_completion);
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "Check out <https://wiki.gnome.org/Apps/Geary>!\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text_with_surrounding_nbsps() throws Error {
        load_body_fixture("&nbsp;&nbsp;I like my space&nbsp;&nbsp;");
        this.test_view.get_text.begin(this.async_completion);
        try {
            assert(this.test_view.get_text.end(async_result()) ==
                   "  I like my space\n\n\n\n");
        } catch (Error err) {
            print("Error: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void update_signature() throws GLib.Error {
        const string BODY = "<p>para</p>";
        load_body_fixture(BODY);
        string html = "";

        const string SIG1 = "signature text 1";
        this.test_view.update_signature(SIG1);
        this.test_view.get_html.begin(this.async_completion);
        html = this.test_view.get_html.end(async_result());
        assert_true(BODY in html, "Body not present");
        assert_true(SIG1 in html, "Signature 1 not present");

        const string SIG2 = "signature text 2";
        this.test_view.update_signature(SIG2);
        this.test_view.get_html.begin(this.async_completion);
        html = this.test_view.get_html.end(async_result());
        assert_true(BODY in html, "Body not present");
        assert_false(SIG1 in html, "Signature 1 still present");
        assert_true(SIG2 in html, "Signature 2 not present");

        this.test_view.update_signature("");
        this.test_view.get_html.begin(this.async_completion);
        html = this.test_view.get_html.end(async_result());
        assert_true(BODY in html, "Body not present");
        assert_false(SIG1 in html, "Signature 1 still present");
        assert_false(SIG2 in html, "Signature 2 still present");
    }

    protected override Composer.WebView set_up_test_view() {
        return new Composer.WebView(this.config);
    }

    protected override void load_body_fixture(string html = "") {
        this.test_view.load_html_headless(html, "", false, false);
        while (this.test_view.is_loading) {
            Gtk.main_iteration();
        }
    }

}
