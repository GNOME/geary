/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class ComposerPageStateTest : ClientWebViewTestCase<ComposerWebView> {

    public const string COMPLETE_BODY_TEMPLATE =
        """<div id="geary-body" dir="auto">%s<div><br></div><div><br></div></div><div id="geary-signature" dir="auto"></div>""";
    public const string CLEAN_BODY_TEMPLATE = "%s<div><br></div><div><br></div>";

    public ComposerPageStateTest() {
        base("ComposerPageStateTest");
        add_test("html_to_text", html_to_text);
        add_test("html_to_text_with_quote", html_to_text_with_quote);
        add_test("html_to_text_with_nested_quote", html_to_text_with_nested_quote);
        add_test("html_to_text_with_blacklist", html_to_text_with_blacklist);
        add_test("edit_context_font", edit_context_font);
        add_test("edit_context_link", edit_context_link);
        add_test("indent_line", indent_line);
        add_test("contains_attachment_keywords", contains_attachment_keywords);
        add_test("clean_content", clean_content);
        add_test("get_html", get_html);
        add_test("get_text", get_text);
        add_test("contains_keywords", contains_keywords);
        add_test("replace_non_breaking_space", replace_non_breaking_space);

        try {
            ComposerWebView.load_resources();
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void html_to_text() throws Error {
        load_body_fixture("<p>para</p>");
        try {
            assert(
                Util.JS.to_string(
                    run_javascript(
                        @"ComposerPageState.htmlToText(window.document.body);"
                    ).get_js_value()
                ) == "para\n\n\n\n"
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void html_to_text_with_quote() throws Error {
        unichar q_marker = Geary.RFC822.Utils.QUOTE_MARKER;
        load_body_fixture("<p>pre</p> <blockquote><p>quote</p></blockquote> <p>post</p>");
        try {
            assert(
                Util.JS.to_string(
                    run_javascript(
                        "ComposerPageState.htmlToText(window.document.body);"
                    ).get_js_value()
                ) == @"pre\n\n$(q_marker)quote\n$(q_marker)\npost\n\n\n\n"
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s", err.message);
            assert_not_reached();
        }
    }

    public void html_to_text_with_nested_quote() throws Error {
        unichar q_marker = Geary.RFC822.Utils.QUOTE_MARKER;
        load_body_fixture("<p>pre</p> <blockquote><p>quote1</p> <blockquote><p>quote2</p></blockquote></blockquote> <p>post</p>");
        try {
            assert(
                Util.JS.to_string(
                    run_javascript(
                        "ComposerPageState.htmlToText(window.document.body)"
                    ).get_js_value()
                ) == @"pre\n\n$(q_marker)quote1\n$(q_marker)\n$(q_marker)$(q_marker)quote2\n$(q_marker)$(q_marker)\npost\n\n\n\n"
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void html_to_text_with_blacklist() throws Error {
        load_body_fixture("<p>pre</p> <blockquote><p>quote1</p> <blockquote><p>quote2</p></blockquote></blockquote> <p>post</p>");
        try {
            assert(
                Util.JS.to_string(
                    run_javascript(
                        "ComposerPageState.htmlToText(window.document.body, [\"blockquote\"])"
                    ).get_js_value()
                ) == @"pre\n\npost\n\n\n\n"
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void edit_context_link() throws Error {
        string html = "<a id=\"test\" href=\"url\">para</a>";
        load_body_fixture(html);

        try {
            assert(
                Util.JS.to_string(
                    run_javascript(@"new EditContext(document.getElementById('test')).encode()")
                    .get_js_value()
                ).has_prefix("1,url,"));
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void edit_context_font() throws Error {
        string html = "<p id=\"test\" style=\"font-family: Comic Sans; font-size: 144\">para</p>";
        load_body_fixture(html);

        try {
            assert(
                Util.JS.to_string(
                    run_javascript(@"new EditContext(document.getElementById('test')).encode()")
                    .get_js_value()
                ) == "0,,Comic Sans,144");
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void indent_line() throws Error {
        load_body_fixture("""<span id="test">some text</span>""");
        try {
            run_javascript(@"SelectionUtil.selectNode(document.getElementById('test'))");
            run_javascript(@"geary.indentLine()");
            assert(
                Util.JS.to_int32(
                    run_javascript(@"document.querySelectorAll('blockquote[type=cite]').length")
                    .get_js_value()
                ) == 1
            );
            assert(
                Util.JS.to_string(
                    run_javascript(@"document.querySelectorAll('blockquote[type=cite]').item(0).innerText")
                    .get_js_value()
                ) == "some text"
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void contains_attachment_keywords() throws Error {
        load_body_fixture_full("""
<blockquote>innerquote</blockquote>

<p>some text</p>

some text
""",
                          "<p>outerquote text</p>",
                          true
            );
        try {
            assert(
                Util.JS.to_bool(
                    run_javascript(@"geary.containsAttachmentKeyword(\"some\", \"subject text\");")
                    .get_js_value()
                )
            );
            assert(
                Util.JS.to_bool(
                    run_javascript(@"geary.containsAttachmentKeyword(\"subject\", \"subject text\");")
                    .get_js_value()
                )
            );
            assert(
                !Util.JS.to_bool(
                    run_javascript(@"geary.containsAttachmentKeyword(\"innerquote\", \"subject text\");")
                    .get_js_value()
                )
            );
            assert(
                !Util.JS.to_bool(
                    run_javascript(@"geary.containsAttachmentKeyword(\"outerquote\", \"subject text\");")
                    .get_js_value()
                )
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void clean_content() throws Error {
        // XXX split these up into multiple tests
        load_body_fixture("""
http://example1.com

<p>http://example2.com</p>

<p>http://example3.com http://example4.com</p>

<a href="blarg">http://example5.com</a>

unknown://example6.com
""");

        string expected = """
<a href="http://example1.com">http://example1.com</a>

<p><a href="http://example2.com">http://example2.com</a></p>

<p><a href="http://example3.com">http://example3.com</a> <a href="http://example4.com">http://example4.com</a></p>

<a href="blarg">http://example5.com</a>

unknown://example6.com
""";

        try {
            run_javascript("geary.cleanContent();");
            assert(
                Util.JS.to_string(
                    run_javascript("geary.bodyPart.innerHTML;")
                    .get_js_value()
                ) == CLEAN_BODY_TEMPLATE.printf(expected)
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_html() throws Error {
        string html = "<p>para</p>";
        load_body_fixture(html);
        try {
            assert(
                Util.JS.to_string(
                   run_javascript(@"window.geary.getHtml();")
                   .get_js_value()
                ) == COMPLETE_BODY_TEMPLATE.printf(html)
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void get_text() throws Error {
        load_body_fixture("<p>para</p>");
        try {
            assert(
                Util.JS.to_string(
                    run_javascript(@"window.geary.getText();")
                    .get_js_value()
                ) == "para\n\n\n\n"
            );
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void contains_keywords() throws Error {
        load_body_fixture();
        string complete_keys = """new Set(["keyword1", "keyword2"])""";
        string suffix_keys = """new Set(["sf1", "sf2"])""";
        try {
            // Doesn't contain
            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('notcontained', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));
            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('not contained', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('not\tcontained', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('http://www.keyword1.com', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('http://www.something.com/something.sf1', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('sf1', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('.sf1', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));


            // Does contain
            assert(Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('keyword1', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('keyword2 contained', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('keyword2\tcontained', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('keyword1.', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('something.sf1', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('something.something.sf2', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

            assert(!Util.JS.to_bool(run_javascript(
                @"ComposerPageState.containsKeywords('http://something/esle.sf2', $complete_keys, $suffix_keys);"
                ).get_js_value()
            ));

        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    public void replace_non_breaking_space() throws Error {
        load_body_fixture();
        string single_nbsp = "a b";
        string multiple_nbsp = "a b c";
        try {
            assert(
                Util.JS.to_string(
                    run_javascript(@"ComposerPageState.replaceNonBreakingSpace('$(single_nbsp)');")
                    .get_js_value()
                ) == "a b");
            assert(
                Util.JS.to_string(
                    run_javascript(@"ComposerPageState.replaceNonBreakingSpace('$(multiple_nbsp)');")
                    .get_js_value()
                ) == "a b c");
        } catch (Util.JS.Error err) {
            print("Util.JS.Error: %s\n", err.message);
            assert_not_reached();
        } catch (Error err) {
            print("WKError: %s\n", err.message);
            assert_not_reached();
        }
    }

    protected override ComposerWebView set_up_test_view() {
        return new ComposerWebView(this.config);
    }

    protected override void load_body_fixture(string body = "") {
        load_body_fixture_full(body, "", true);
    }

    protected void load_body_fixture_full(string body,
                                          string quote,
                                          bool top_posting) {
        this.test_view.load_html(body, quote, top_posting, false);
        while (this.test_view.is_loading) {
            Gtk.main_iteration();
        }
    }

}
