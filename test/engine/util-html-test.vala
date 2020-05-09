/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.HTML.UtilTest : TestCase {

    public UtilTest() {
        base("Geary.HTML.Util");
        add_test("preserve_whitespace", preserve_whitespace);
        add_test("smart_escape_div", smart_escape_div);
        add_test("smart_escape_no_closing_tag", smart_escape_no_closing_tag);
        add_test("smart_escape_img", smart_escape_img);
        add_test("smart_escape_xhtml_img", smart_escape_xhtml_img);
        add_test("smart_escape_mixed", smart_escape_mixed);
        add_test("smart_escape_text", smart_escape_text);
        add_test("smart_escape_text_url", smart_escape_text_url);
        add_test("remove_html_tags", remove_html_tags);
    }

    public void preserve_whitespace() throws GLib.Error {
        assert_equal(smart_escape("some text"), "some text");
        assert_equal(smart_escape("some  text"), "some &nbsp;text");
        assert_equal(smart_escape("some   text"), "some &nbsp;&nbsp;text");
        assert_equal(smart_escape("some\ttext"), "some &nbsp;&nbsp;&nbsp;text");

        assert_equal(smart_escape("some\ntext"), "some<br>text");
        assert_equal(smart_escape("some\rtext"), "some<br>text");
        assert_equal(smart_escape("some\r\ntext"), "some<br>text");

        assert_equal(smart_escape("some\n\ntext"), "some<br><br>text");
        assert_equal(smart_escape("some\r\rtext"), "some<br><br>text");
        assert_equal(smart_escape("some\n\rtext"), "some<br><br>text");
        assert_equal(smart_escape("some\r\n\r\ntext"), "some<br><br>text");
    }

    public void smart_escape_div() throws Error {
        string html = "<div>ohhai</div>";
        assert_equal(smart_escape(html), html);
    }

    public void smart_escape_no_closing_tag() throws Error {
        string html = "<div>ohhai";
        assert_equal(smart_escape(html), html);
    }

    public void smart_escape_img() throws Error {
        string html = "<img src=\"http://example.com/lol.gif\">";
        assert_equal(smart_escape(html), html);
    }

    public void smart_escape_xhtml_img() throws Error {
        string html = "<img src=\"http://example.com/lol.gif\"/>";
        assert_equal(smart_escape(html), html);
    }

    public void smart_escape_mixed() throws Error {
        string html = "mixed <div>ohhai</div> text";
        assert_equal(smart_escape(html), html);
    }

    public void smart_escape_text() throws GLib.Error {
        assert_equal(smart_escape("some text"), "some text");
        assert_equal(smart_escape("<some text"), "&lt;some text");
        assert_equal(smart_escape("some text>"), "some text&gt;");
    }

    public void smart_escape_text_url() throws GLib.Error {
        assert_equal(
            smart_escape("<http://example.com>"),
            "&lt;http://example.com&gt;"
        );
        assert_equal(
            smart_escape("<http://example.com>"),
            "&lt;http://example.com&gt;"
        );
    }

    public void remove_html_tags() throws Error {
        string blockquote_body = """<blockquote>hello</blockquote> <p>there</p>""";

        string style_complete = """<style>
.bodyblack { font-family: Verdana, Arial, Helvetica, sans-serif; font-size:
 12px; }
td { font-size: 12px; }
.footer { font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10
px; }
</style>""";

        string style_truncated = """<html><head>
<meta http-equiv=Content-Type content="text/html; charset=utf-8">
<style>
.bodyblack { font-family: Verdana, """;

        assert_equal(html_to_text(HTML_BODY_COMPLETE), HTML_BODY_COMPLETE_EXPECTED);
        assert_equal(html_to_text(blockquote_body), "hello\n there\n");
        assert_equal(html_to_text(blockquote_body, false), " there\n");
        assert_equal(html_to_text(HTML_ENTITIES_BODY), HTML_ENTITIES_EXPECTED);
        assert_string(html_to_text(style_complete)).is_empty();
        assert_string(html_to_text(style_complete)).is_empty();
        assert_string(html_to_text(style_truncated)).is_empty();
    }

    private static string HTML_BODY_COMPLETE = """<html><head>
<meta http-equiv=Content-Type content="text/html; charset=utf-8">
<style>
.bodyblack { font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 12px; }
td { font-size: 12px; }
.footer { font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10px; }
</style>
</head>
<body><table cellSpacing="0" cellPadding="0" width="450" border="0" class="bodyblack"><tr><td>
<p><br />Hi Kenneth, <br /> <br /> We xxxxx xxxx xx xxx xxx xx xxxx x xxxxxxxx xxxxxxxx.
<br /> <br /> <br /> <br />Thank you, <br /> <br />XXXXX
X XXXXXX<br /><br />You can reply directly to this message or click the following link:<br /><a href="https://app.foobar.com/xxxxxxxx752a0ab01641966deff6c48623aba">https://app.foobar.com/xxxxxxxxxxxxxxxx1641966deff6c48623aba</a><br /><br />You can change your email preferences at:<br /><a href="https://app.foobar.com/xxxxxxxxxxxxx">https://app.foobar.com/xxxxxxxxxxx</a></p></td></tr>
</table></body></html>
""";

    private static string HTML_BODY_COMPLETE_EXPECTED = """

Hi Kenneth, 

 We xxxxx xxxx xx xxx xxx xx xxxx x xxxxxxxx xxxxxxxx.




Thank you, 

XXXXX
X XXXXXX

You can reply directly to this message or click the following link:
https://app.foobar.com/xxxxxxxxxxxxxxxx1641966deff6c48623aba

You can change your email preferences at:
https://app.foobar.com/xxxxxxxxxxx
 
""";

        private static string HTML_ENTITIES_BODY = """<html><head></head><body><div style="font-family: Verdana;font-size: 12.0px;"><div>
<div style="font-family: Verdana;font-size: 12.0px;">
<div>What if I said that I&#39;d like to go to the theater tomorrow night.</div>

<div>&nbsp;</div>

<div>I think we could do that!</div>
""";

        private static string HTML_ENTITIES_EXPECTED = """

What if I said that I'd like to go to the theater tomorrow night.


 


I think we could do that!



""";

}
