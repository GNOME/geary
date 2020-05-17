/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.Utils.Test : TestCase {

    public Test() {
        base("Geary.RFC822.Utils.Test");
        add_test("to_preview_text", to_preview_text);
        add_test("best_encoding_default", best_encoding_default);
        add_test("best_encoding_long_line", best_encoding_long_line);
        add_test("best_encoding_binary", best_encoding_binary);
    }

    public void to_preview_text() throws GLib.Error {
        assert(Geary.RFC822.Utils.to_preview_text(PLAIN_BODY_ENCODED, Geary.RFC822.TextFormat.PLAIN) ==
               PLAIN_BODY_EXPECTED);
        assert(Geary.RFC822.Utils.to_preview_text(HTML_BODY_ENCODED, Geary.RFC822.TextFormat.HTML) ==
               HTML_BODY_EXPECTED);
        assert(Geary.RFC822.Utils.to_preview_text(HTML_BODY_ENCODED, Geary.RFC822.TextFormat.HTML) ==
               HTML_BODY_EXPECTED);
    }

    public void best_encoding_default() throws GLib.Error {
        string test = "abc";
        var stream = new GMime.StreamMem.with_buffer(test.data);
        get_best_encoding.begin(stream, 7BIT, null, this.async_completion);
        var encoding = get_best_encoding.end(async_result());
        assert_true(encoding == DEFAULT);
    }

    public void best_encoding_long_line() throws GLib.Error {
        GLib.StringBuilder buf = new GLib.StringBuilder();
        for (int i = 0; i < 2000; i++) {
            buf.append("long ");
        }
        var stream = new GMime.StreamMem.with_buffer(buf.str.data);
        get_best_encoding.begin(stream, 7BIT, null, this.async_completion);
        var encoding = get_best_encoding.end(async_result());
        assert_true(encoding == QUOTEDPRINTABLE);
    }

    public void best_encoding_binary() throws GLib.Error {
        uint8 test[] = { 0x20, 0x00, 0x20 };
        var stream = new GMime.StreamMem.with_buffer(test);
        get_best_encoding.begin(stream, 7BIT, null, this.async_completion);
        var encoding = get_best_encoding.end(async_result());
        assert_true(encoding == BASE64);
    }


    public static string PLAIN_BODY_ENCODED = "-----BEGIN PGP SIGNED MESSAGE-----\nHash: SHA512\n\n=============================================================================\nFreeBSD-EN-16:11.vmbus                                          Errata Notice\n                                                          The FreeBSD Project\n\nTopic:          Avoid using spin locks for channel message locks\n\nCategory:       core\nModule:         vmbus\nAnnounced:      2016-08-12\nCredits:        Microsoft OSTC\nAffects:        FreeBSD 10.3\nCorrected:      2016-06-15 09:52:01 UTC (stable/10, 10.3-STABLE)\n                2016-08-12 04:01:16 UTC (releng/10.3, 10.3-RELEASE-p7)\n\nFor general information regarding FreeBSD Errata Notices and Security\nAdvisories, including descriptions of the fields above, security\nbranches, and the following sections, please visit\n<URL:https://security.FreeBSD.org/>.\n";
    public static string PLAIN_BODY_EXPECTED = "FreeBSD-EN-16:11.vmbus Errata Notice The FreeBSD Project Topic: Avoid using spin locks for channel message locks Category: core Module: vmbus Announced: 2016-08-12 Credits: Microsoft OSTC Affects: FreeBSD 10.3 Corrected: 2016-06-15 09:52:01 UTC (stable/10, 10.3-STABLE) 2016-08-12 04:01:16 UTC (releng/10.3, 10.3-RELEASE-p7) For general information regarding FreeBSD Errata Notices and Security Advisories, including descriptions of the fields above, security branches, and the following sections, please visit <URL:https://security.FreeBSD.org/>.";

    public static string HTML_BODY_ENCODED = """<html><head>
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

    public static string HTML_BODY_EXPECTED = "Hi Kenneth, We xxxxx xxxx xx xxx xxx xx xxxx x xxxxxxxx xxxxxxxx. Thank you, XXXXX X XXXXXX You can reply directly to this message or click the following link: https://app.foobar.com/xxxxxxxxxxxxxxxx1641966deff6c48623aba You can change your email preferences at: https://app.foobar.com/xxxxxxxxxxx";

}
