/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.Utils.Test : Gee.TestCase {

    public Test() {
        base("Geary.RFC822.Utils.Test");
        add_test("to_preview_text", to_preview_text);
    }

    public void to_preview_text() {
        assert(Geary.RFC822.Utils.to_preview_text(PLAIN_BODY_ENCODED, Geary.RFC822.TextFormat.PLAIN) ==
               PLAIN_BODY_EXPECTED.substring(0, Geary.Email.MAX_PREVIEW_BYTES));
        assert(Geary.RFC822.Utils.to_preview_text(HTML_BODY_ENCODED, Geary.RFC822.TextFormat.HTML) ==
               HTML_BODY_EXPECTED.substring(0, Geary.Email.MAX_PREVIEW_BYTES));
        assert(Geary.RFC822.Utils.to_preview_text(HTML_BODY_ENCODED, Geary.RFC822.TextFormat.HTML) ==
               HTML_BODY_EXPECTED.substring(0, Geary.Email.MAX_PREVIEW_BYTES));
    }

    public static string PLAIN_BODY_ENCODED = "Content-Type: text/plain; charset=\"us-ascii\"\r\nContent-Transfer-Encoding: 7bit\r\n\r\n-----BEGIN PGP SIGNED MESSAGE-----\r\nHash: SHA512\r\n\r\n=============================================================================\r\nFreeBSD-EN-16:11.vmbus                                          Errata Notice\r\n                                                          The FreeBSD Project\r\n\r\nTopic:          Avoid using spin locks for channel message locks\r\n\r\nCategory:       core\r\nModule:         vmbus\r\nAnnounced:      2016-08-12\r\nCredits:        Microsoft OSTC\r\nAffects:        FreeBSD 10.3\r\nCorrected:      2016-06-15 09:52:01 UTC (stable/10, 10.3-STABLE)\r\n                2016-08-12 04:01:16 UTC (releng/10.3, 10.3-RELEASE-p7)\r\n\r\nFor general information regarding FreeBSD Errata Notices and Security\r\nAdvisories, including descriptions of the fields above, security\r\nbranches, and the following sections, please visit\r\n<URL:https://security.FreeBSD.org/>.\r\n";

    public static string PLAIN_BODY_EXPECTED = "FreeBSD-EN-16:11.vmbus Errata Notice The FreeBSD Project Topic: Avoid using spin locks for channel message locks Category: core Module: vmbus Announced: 2016-08-12 Credits: Microsoft OSTC Affects: FreeBSD 10.3 Corrected: 2016-06-15 09:52:01 UTC (stable/10, 10.3-STABLE) 2016-08-12 04:01:16 UTC (releng/10.3, 10.3-RELEASE-p7)";

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
