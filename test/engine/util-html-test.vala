/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.HTML.UtilTest : Gee.TestCase {

    public UtilTest() {
        base("Geary.HTML.Util");
        add_test("remove_html_tags", remove_html_tags);
    }

    public void remove_html_tags() {
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

        assert(Geary.HTML.html_to_text(HTML_BODY_COMPLETE) == HTML_BODY_COMPLETE_EXPECTED);
        assert(Geary.HTML.html_to_text(blockquote_body) == "hello\n there\n");
        assert(Geary.HTML.html_to_text(blockquote_body, false) == " there\n");
        assert(Geary.HTML.html_to_text(style_complete) == "");
        assert(Geary.HTML.html_to_text(style_complete) == "");
        assert(Geary.HTML.html_to_text(style_truncated) == "");
    }

    public static string HTML_BODY_COMPLETE = """<html><head>
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

    public static string HTML_BODY_COMPLETE_EXPECTED = """

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

}
