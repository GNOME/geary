/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.MessageDataTest : TestCase {

    public MessageDataTest() {
        base("Geary.RFC822.MessageDataTest");
        add_test("subject_from_rfc822", subject_from_rfc822);
        add_test("date_from_rfc822", date_from_rfc822);
        add_test("date_from_rfc822", date_from_rfc822);
        add_test("date_to_rfc822", date_to_rfc822);
        add_test("header_from_rfc822", header_from_rfc822);
        add_test("header_names_from_rfc822", header_names_from_rfc822);
        add_test("PreviewText.with_header", preview_text_with_header);
        add_test("MessageId.from_rfc822_string", message_id_from_rfc822_string);
        add_test("MessageId.to_rfc822_string", message_id_to_rfc822_string);
        add_test("MessageIdList.from_rfc822_string", message_id_list_from_rfc822_string);
        add_test("MessageIdList.merge", message_id_list_merge);
    }

    public void subject_from_rfc822() throws GLib.Error {
        Subject plain = new Subject.from_rfc822_string("hello");
        assert_equal(plain.to_string(), "hello");

        Subject new_line = new Subject.from_rfc822_string("hello\n there");
        assert_equal(new_line.to_string(), "hello there");
    }

    public void preview_text_with_header() throws GLib.Error {
        PreviewText plain_preview1 = new PreviewText.with_header(
            new Geary.Memory.StringBuffer(PLAIN_BODY1_HEADERS),
            new Geary.Memory.StringBuffer(PLAIN_BODY1_ENCODED)
        );
        assert_equal(plain_preview1.buffer.to_string(), PLAIN_BODY1_EXPECTED);

        PreviewText base64_preview = new PreviewText.with_header(
            new Geary.Memory.StringBuffer(BASE64_BODY_HEADERS),
            new Geary.Memory.StringBuffer(BASE64_BODY_ENCODED)
        );
        assert_equal(base64_preview.buffer.to_string(), BASE64_BODY_EXPECTED);

        string html_part_headers = "Content-Type: text/html; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n";

        PreviewText html_preview1 = new PreviewText.with_header(
            new Geary.Memory.StringBuffer(html_part_headers),
            new Geary.Memory.StringBuffer(HTML_BODY1_ENCODED)
        );
        assert_equal(html_preview1.buffer.to_string(), HTML_BODY1_EXPECTED);

        PreviewText html_preview2 = new PreviewText.with_header(
            new Geary.Memory.StringBuffer(html_part_headers),
            new Geary.Memory.StringBuffer(HTML_BODY2_ENCODED)
        );
        assert_equal(html_preview2.buffer.to_string(), HTML_BODY2_EXPECTED);
    }

    public void header_from_rfc822() throws GLib.Error {
        Header test_article = new Header(new Memory.StringBuffer(HEADER_FIXTURE));
        assert_equal(test_article.get_header("From"), "Test <test@example.com>");
        assert_equal(test_article.get_header("Subject"), "test");
        assert_null(test_article.get_header("Blah"));
    }

    public void header_names_from_rfc822() throws GLib.Error {
        Header test_article = new Header(new Memory.StringBuffer(HEADER_FIXTURE));
        assert_equal<int?>(test_article.get_header_names().length, 2);
        assert_equal(test_article.get_header_names()[0], "From");
        assert_equal(test_article.get_header_names()[1], "Subject");
    }

    public void date_from_rfc822() throws GLib.Error {
        const string FULL_HOUR_TZ = "Thu, 28 Feb 2019 00:00:00 -0100";
        Date full_hour_tz = new Date.from_rfc822_string(FULL_HOUR_TZ);
        assert_equal<int64?>(
            full_hour_tz.value.get_utc_offset(),
            ((int64) (-1 * 3600)) * 1000 * 1000,
            "full_hour_tz.value.get_utc_offset"
        );
        assert_equal<int?>(full_hour_tz.value.get_hour(), 0, "full_hour_tz hour");
        assert_equal<int?>(full_hour_tz.value.get_minute(), 0, "full_hour_tz minute");
        assert_equal<int?>(full_hour_tz.value.get_second(), 0, "full_hour_tz second");
        assert_equal<int?>(full_hour_tz.value.get_day_of_month(), 28, "full_hour_tz day");
        assert_equal<int?>(full_hour_tz.value.get_month(), 2, "full_hour_tz month");
        assert_equal<int?>(full_hour_tz.value.get_year(), 2019, "full_hour_tz year");

        assert_equal<int64?>(
            full_hour_tz.value.to_unix(),
            full_hour_tz.value.to_utc().to_unix(),
            "to_unix not UTC"
        );

        const string HALF_HOUR_TZ = "Thu, 28 Feb 2019 00:00:00 +1030";
        Date half_hour_tz = new Date.from_rfc822_string(HALF_HOUR_TZ);
        assert_equal<int64?>(
            half_hour_tz.value.get_utc_offset(),
            ((int64) (10.5 * 3600)) * 1000 * 1000
        );
        assert_equal<int?>(half_hour_tz.value.get_hour(), 0);
        assert_equal<int?>(half_hour_tz.value.get_minute(), 0);
        assert_equal<int?>(half_hour_tz.value.get_second(), 0);
        assert_equal<int?>(half_hour_tz.value.get_day_of_month(), 28);
        assert_equal<int?>(half_hour_tz.value.get_month(), 2);
        assert_equal<int?>(half_hour_tz.value.get_year(), 2019);
    }

    public void date_to_rfc822() throws GLib.Error {
        const string FULL_HOUR_TZ = "Thu, 28 Feb 2019 00:00:00 -0100";
        Date full_hour_tz = new Date.from_rfc822_string(FULL_HOUR_TZ);
        assert_equal(full_hour_tz.to_rfc822_string(), FULL_HOUR_TZ);

        const string HALF_HOUR_TZ = "Thu, 28 Feb 2019 00:00:00 +1030";
        Date half_hour_tz = new Date.from_rfc822_string(HALF_HOUR_TZ);
        assert_equal(half_hour_tz.to_rfc822_string(), HALF_HOUR_TZ);

        const string NEG_HALF_HOUR_TZ = "Thu, 28 Feb 2019 00:00:00 -1030";
        Date neg_half_hour_tz = new Date.from_rfc822_string(NEG_HALF_HOUR_TZ);
        assert_equal(neg_half_hour_tz.to_rfc822_string(), NEG_HALF_HOUR_TZ);
    }


    public void message_id_from_rfc822_string() throws GLib.Error {
        assert_equal(
            new MessageID.from_rfc822_string("<note_895184@gitlab.gnome.org>").value,
            "note_895184@gitlab.gnome.org"
        );
        assert_equal(
            new MessageID.from_rfc822_string(" <note_895184@gitlab.gnome.org>\n").value,
            "note_895184@gitlab.gnome.org"
        );
        assert_equal(
            new MessageID.from_rfc822_string("note_895184@gitlab.gnome.org").value,
            "note_895184@gitlab.gnome.org"
        );
        assert_equal(
            new MessageID.from_rfc822_string(" note_895184@gitlab.gnome.org\n").value,
            "note_895184@gitlab.gnome.org"
        );
        assert_equal(
            new MessageID.from_rfc822_string("(note_895184@gitlab.gnome.org)").value,
            "note_895184@gitlab.gnome.org"
        );
        assert_equal(
            new MessageID.from_rfc822_string("<note_895184>").value,
           "note_895184"
        );
        assert_equal(
            new MessageID.from_rfc822_string("<note 895184>").value,
            "note 895184"
        );
        assert_equal(
            new MessageID.from_rfc822_string("<id1> <id2>").value,
            "id1"
        );

        try {
            new MessageID.from_rfc822_string("");
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(err, new Error.INVALID(""));
        }
        try {
            new MessageID.from_rfc822_string(" ");
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(err, new Error.INVALID(""));
        }
        try {
            new MessageID.from_rfc822_string(" \n");
            assert_not_reached();
        } catch (GLib.Error err) {
            assert_error(err, new Error.INVALID(""));
        }
    }

    public void message_id_to_rfc822_string() throws GLib.Error {
        assert_equal(
            new MessageID("note_895184@gitlab.gnome.org").to_rfc822_string(),
            "<note_895184@gitlab.gnome.org>"
        );
        assert_equal(
            new MessageID.from_rfc822_string("<note_895184@gitlab.gnome.org>").to_rfc822_string(),
            "<note_895184@gitlab.gnome.org>"
        );
        assert_equal(
            new MessageID.from_rfc822_string(" <note_895184@gitlab.gnome.org>\n").to_rfc822_string(),
            "<note_895184@gitlab.gnome.org>"
        );
    }

    public void message_id_list_from_rfc822_string() throws GLib.Error {

        // Standard variants

        assert_collection(
            new MessageIDList.from_rfc822_string("<id@example.com>").get_all(),
            "<id@example.com>"
        )
        .size(1)
        .contains(new MessageID("id@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("<id1@example.com><id2@example.com>").get_all(),
            "<id1@example.com><id2@example.com>"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("<id1@example.com> <id2@example.com>").get_all(),
            "<id1@example.com> <id2@example.com>"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        // Parens as delim are invalid but seen in the wild

        assert_collection(
            new MessageIDList.from_rfc822_string("(id@example.com)").get_all(),
            "(id@example.com)"
        )
        .size(1)
        .contains(new MessageID("id@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("(id1@example.com)(id2@example.com>").get_all(),
            "(id1@example.com)(id2@example.com>"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("(id1@example.com) (id2@example.com)").get_all(),
            "(id1@example.com) (id2@example.com)"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        // No delimiters

        assert_collection(
            new MessageIDList.from_rfc822_string("id@example.com").get_all(),
            "id@example.com"
        )
        .size(1)
        .contains(new MessageID("id@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("id1@example.com id2@example.com").get_all(),
            "id1@example.com id2@example.com"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        // Comma-separated is invalid but seen in the wild

        assert_collection(
            new MessageIDList.from_rfc822_string("<id1@example.com>,<id2@example.com>").get_all(),
            "<id1@example.com>,<id2@example.com>"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("<id1@example.com>, <id2@example.com>").get_all(),
            "<id1@example.com>, <id2@example.com>"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("(id1@example.com),(id2@example.com)").get_all(),
            "(id1@example.com),(id2@example.com)"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));

        assert_collection(
            new MessageIDList.from_rfc822_string("(id1@example.com), (id2@example.com)").get_all(),
            "(id1@example.com), (id2@example.com)"
        )
        .size(2)
        .contains(new MessageID("id1@example.com"))
        .contains(new MessageID("id2@example.com"));
    }

    public void message_id_list_merge() throws GLib.Error {
        var a1 = new MessageID("a");
        var b = new MessageID("b");
        var a2 = new MessageID("a");
        var list = new MessageIDList.single(a1);

        assert_equal<int?>(list.merge_id(b).size, 2);
        assert_equal<int?>(list.merge_id(a2).size, 1);

        assert_equal<int?>(list.merge_list(new MessageIDList.single(b)).size, 2);
        assert_equal<int?>(list.merge_list(new MessageIDList.single(a2)).size, 1);
    }


    private const string HEADER_FIXTURE = """From: Test <test@example.com>
Subject: test

""";

    public static string PLAIN_BODY1_HEADERS = "Content-Type: text/plain; charset=\"us-ascii\"\r\nContent-Transfer-Encoding: 7bit\r\n";
    public static string PLAIN_BODY1_ENCODED = "-----BEGIN PGP SIGNED MESSAGE-----\r\nHash: SHA512\r\n\r\n=============================================================================\r\nFreeBSD-EN-16:11.vmbus                                          Errata Notice\r\n                                                          The FreeBSD Project\r\n\r\nTopic:          Avoid using spin locks for channel message locks\r\n\r\nCategory:       core\r\nModule:         vmbus\r\nAnnounced:      2016-08-12\r\nCredits:        Microsoft OSTC\r\nAffects:        FreeBSD 10.3\r\nCorrected:      2016-06-15 09:52:01 UTC (stable/10, 10.3-STABLE)\r\n                2016-08-12 04:01:16 UTC (releng/10.3, 10.3-RELEASE-p7)\r\n\r\nFor general information regarding FreeBSD Errata Notices and Security\r\nAdvisories, including descriptions of the fields above, security\r\nbranches, and the following sections, please visit\r\n<URL:https://security.FreeBSD.org/>.\r\n";
    public static string PLAIN_BODY1_EXPECTED = "FreeBSD-EN-16:11.vmbus Errata Notice The FreeBSD Project Topic: Avoid using spin locks for channel message locks Category: core Module: vmbus Announced: 2016-08-12 Credits: Microsoft OSTC Affects: FreeBSD 10.3 Corrected: 2016-06-15 09:52:01 UTC (stable/10, 10.3-STABLE) 2016-08-12 04:01:16 UTC (releng/10.3, 10.3-RELEASE-p7) For general information regarding FreeBSD Errata Notices and Security Advisories, including descriptions of the fields above, security branches, and the following sections, please visit <URL:https://security.FreeBSD.org/>.";

    public static string BASE64_BODY_HEADERS = "Content-Transfer-Encoding: base64\r\nContent-Type: text/plain; charset=\"utf-8\"; Format=\"flowed\"\r\n";
    public static string BASE64_BODY_ENCODED = "CkhleSBSaWNhcmRvLAoKVGhhbmtzIGZvciBsb29raW5nIGludG8gdGhpcy4KCk9uIFR1ZSwgRGVj\r\nIDEzLCAyMDE2IGF0IDEwOjIzIEFNLCBSaWNhcmRvIEJ1Z2FsaG8gPHJidWdhbGhvQGdtYWlsLmNv\r\nbT4gCndyb3RlOgo+IGZyb20gbXkgdGVzdGluZywgdGhlIHByZWZldGNoX3BlcmlvZF9kYXlzIGRv\r\nZXMgbm90IHdvcmsgZm9yIElOQk9YLgo+IFRoaXMgaXMgYW5ub3lpbmcsIEkgd2FudCB0byBwcmVm\r\nZXRjaCBhbGwgbXkgZS1tYWlsLCBzbyBJIGNhbiBydW4gCj4gc2VhcmNoCj4gZXMuCj4gCj4gQXMg\r\nZmFyIGFzIEkgY291bGQsIEkndmUgdHJhY2VkIHRoZSBwcm9ibGVtIGRvd24gdG8gdGhpcyBjb25k\r\naXRpb24gaW4KPiBzZW5kX2FsbDoKPiAKPiAgICAgaWYgKGltYXBfZm9sZGVyLmdldF9vcGVuX3N0\r\nYXRlKCkgIT0gRm9sZGVyLk9wZW5TdGF0ZS5DTE9TRUQpCj4gICAgICAgICAgICAgICAgIGNvbnRp\r\nbnVlOwo+IAo+IGh0dHBzOi8vZ2l0aHViLmNvbS9HTk9NRS9nZWFyeS9ibG9iL21hc3Rlci9zcmMv\r\nZW5naW5lL2ltYXAtZW5naW5lL2ltYXAtCj4gZW5naW5lLWFjY291bnQtc3luY2hyb25pemVyLnZh\r\nbGEjTDE1MQo+IAo+IElOQk9YIGlzIGFsd2F5cyBvcGVuIGFuZCB0aHVzIGlzIG5ldmVyIHNlbnQg\r\ndG8gcHJvY2Vzc19xdWV1ZV9hc3luYy4KPiAKPi";
    public static string BASE64_BODY_EXPECTED = "Hey Ricardo, Thanks for looking into this. On Tue, Dec 13, 2016 at 10:23 AM, Ricardo Bugalho <rbugalho@gmail.com> wrote:";

    public static string HTML_BODY1_ENCODED = """<html><head>
<meta http-equiv=3DContent-Type content=3D"text/html; charset=3Dutf-8">
<style>
.bodyblack { font-family: Verdana, Arial, Helvetica, sans-serif; font-size:=
 12px; }
td { font-size: 12px; }
.footer { font-family: Verdana, Arial, Helvetica, sans-serif; font-size: 10=
px; }
</style>
</head>
<body><table cellSpacing=3D"0" cellPadding=3D"0" width=3D"450" border=3D"0"=
 class=3D"bodyblack"><tr><td>
<p><br />Hi Kenneth, <br /> <br /> We xxxxx xxxx xx xxx xxx xx xxxx x xxxxx=
xxx xxxxxxxx.=C2=A0<br /> <br /> <br /> <br />Thank you, <br /> <br />XXXXX=
X XXXXXX<br /><br />You can reply directly to this message or click the fol=
lowing link:<br /><a href=3D"https://app.foobar.com/xxxxxxxx752a0ab01641966=
deff6c48623aba">https://app.foobar.com/xxxxxxxxxxxxxxxx1641966deff6c48623ab=
a</a><br /><br />You can change your email preferences at:<br /><a href=3D"=
https://app.foobar.com/xxxxxxxxxxxxx">https://app.foobar.com/xxxxxxxxxxx</a=
></p></td></tr>
</table></body></html>""";

    public static string HTML_BODY1_EXPECTED = "Hi Kenneth, We xxxxx xxxx xx xxx xxx xx xxxx x xxxxxxxx xxxxxxxx. Thank you, XXXXXX XXXXXX You can reply directly to this message or click the following link: https://app.foobar.com/xxxxxxxxxxxxxxxx1641966deff6c48623aba You can change your email preferences at: https://app.foobar.com/xxxxxxxxxxx";

    public static string HTML_BODY2_ENCODED = """<!DOCTYPE html>
<!--2c2a1c66-0638-7c87-5057-bff8be4291eb_v180-->
<html>
  <head>
    <meta http-equiv=3D"Content-Type" content=3D"text/html; charset=3Dutf-8=
"></meta><style type=3D"text/css">
@media only screen and (max-width: 620px) {
body[yahoo] .device-width {
width: 450px !important
}
body[yahoo] .center {
text-align: center !important
}
}
@media only screen and (max-width: 479px) {
body[yahoo] .device-width {
width: 300px !important;
padding: 0
}
body[yahoo] .mobile-full-width {
width: 300px !important
}
}
body[yahoo] .mobile-full-width {
min-width: 103px;
max-width: 300px;
height: 38px;
}
body[yahoo] .mobile-full-width a {
display: block;
padding: 10px 0;
}
body[yahoo] .mobile-full-width td{
padding: 0px !important
}
body { width: 100% !important; -webkit-text-size-adjust: 100% !important; -=
ms-text-size-adjust: 100% !important; -webkit-font-smoothing: antialiased !=
important; margin: 0 !important; padding: 0 0 100px !important; font-family=
: Helvetica, Arial, sans-serif !important; background-color:#f9f9f9}
.ReadMsgBody { width: 100% !important; background-color: #ffffff !important=
; }
.ExternalClass { width: 100% !important; }
.ExternalClass { line-height: 100% !important; }
img { display: block !important; outline: none !important; text-decoration:=
 none !important; -ms-interpolation-mode: bicubic !important; }
td{word-wrap: break-word;}
.blueLinks a {
color: #0654ba !important;
text-decoration: none !important;
}
.whiteLinks a {
color: #ffffff !important;
text-decoration: none !important;
font-weight: bold !important;
}
.wrapper {
width: 100%;
table-layout: fixed;
-webkit-text-size-adjust: 100%;
-ms-text-size-adjust: 100%;
}
.webkit {
max-width: 100%;
margin: 0 auto;
}
</style> <!--[if gte mso 9]>
<style>td.product-details-block{word-break:break-all}.threeColumns{width:14=
0px !important}.threeColumnsTd{padding:10px 20px !important}.fourColumns{wi=
dth:158px !important}.fourColumnsPad{padding: 0 18px 0 0 !important}.fourCo=
lumnsTd{padding:10px 0px !important}.twoColumnSixty{width:360px !important}=
table{mso-table-lspace:0pt; mso-table-rspace:0pt;}</style>
<![endif]-->
<style type=3D"text/css">
@media only screen and (max-width: 2000px) {
*[class=3Dcta-block] {
padding: 24px 0 24px 0px !important;
}
*[class=3Dcta-block-2] {
padding: 24px 0 8px 0px !important;
}
*[class=3Dcta-block-3] {
padding: 8px 0 24px 0px !important;
}
}
@media only screen and (max-width: 620px) {
*[class=3Dcta-block] {
padding: 24px 0 24px 0px !important;
}
*[class=3Dcta-block-2] {
padding: 24px 0 8px 0px !important;
}
*[class=3Dcta-block-3] {
padding: 8px 0 24px 0px !important;
}
}
@media screen and (max-width:480px) {
*[class=3Dcta-block] {
padding: 24px 0 24px !important;
}
*[class=3Dcta-block-2] {
padding: 24px 0 8px !important;
}
*[class=3Dcta-block-3] {
padding: 8px 0 24px !important;
}
*[class=3Dmobile-ebayLogo] {
padding: 8px 0 8px !important;
}
*[class=3Dmobile-multi-item-left-image] {
padding: 8px 15px 8px 0 !important;
}
*[class=3Dmobile-multi-item-right-image] {
padding: 8px 0 8px 15px !important;
}
*[class=3Dmobile-dealmaker-headline] {
font-size: 20px !important;
line-height: 23px !important;
}
td.mobile-dealmaker-CTA1 {
width: 303px !important;
}
}
</style>
  </head>
  <body yahoo=3D"fix"> <center class=3D"wrapper" style=3D"background-color:=
 #f9f9f9">
        <div class=3D"webkit" style=3D"background-color: #f9f9f9"> <table i=
d=3D"area2Container" width=3D"100%" border=3D"0" cellpadding=3D"0" cellspac=
ing=3D"0" align=3D"center" style=3D"border-collapse: collapse !important; b=
order-spacing: 0 !important; border: none; background-color:#f9f9f9">
<tr>
<td width=3D"100%" valign=3D"top" style=3D"border-collapse: collapse !impor=
tant; border-spacing: 0 !important; border: none;">
<table class=3D"device-width" style=3D"border-collapse: collapse !important=
; border-spacing: 0 !important; border: none;" align=3D"center" bgcolor=3D"=
#f9f9f9" border=3D"0" cellpadding=3D"0" cellspacing=3D"0" width=3D"600">
<tbody>
<tr>
<td height=3D"1" valign=3D"top" style=3D"border-collapse: collapse !importa=
nt; border-spacing: 0 !important; padding: 0; border: none; font-size: 1px;=
 line-height: 1px; color: #f9f9f9">
Buy It Now from US $1,750.00 to US $5,950.00.
</td>
</tr>
</tbody>
</table>
</td>
</tr>
</table> <table id=3D"area4Container" width=3D"100%" border=3D"0" cellpaddi=
ng=3D"0" cellspacing=3D"0" align=3D"center" style=3D"border-collapse: colla=
pse !important; border-spacing: 0 !important; border: none; background-colo=
r:#f9f9f9">
<tr>
<td width=3D"100%" valign=3D"top" style=3D"border-collapse: collapse !impor=
tant; border-spacing: 0 !important; border: none;">
<table width=3D"600" class=3D"device-width" border=3D"0" cellpadding=3D"0" =
cellspacing=3D"0" align=3D"center" style=3D"border-collapse: collapse !impo=
rtant; border-spacing: 0 !important; border: none;">
<tr>
<td class=3D"mobile-ebayLogo" valign=3D"top" style=3D"border-collapse: coll=
apse !important; border-spacing: 0 !important; padding: 16px 0 16px; border=
: none;"><a href=3D"http://rover.ebay.com/rover/0/e11021.m1831.l3127/7?euid=
=3Dd9f42b5e860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Fwww=
.ebay.com.au%2Fulk%2Fstart%2Fshop&exe=3D15083&ext=3D38992&sojTags=3Dexe=3De=
xe,ext=3Dext,bu=3Dbu" style=3D"text-decoration: none; color: #0654ba;"><img=
 src=3D"http://p.ebaystatic.com/aw/email/eBayLogo.png" width=3D"133" border=
=3D"0" alt=3D"eBay" align=3D"left" style=3D"display: inline block; outline:=
 none; text-decoration: none; -ms-interpolation-mode: bicubic; border: none=
;" /></a><img src=3D"http://rover.ebay.com/roveropen/0/e11021/7?euid=3Dd9f4=
2b5e860b4eabb98195c2888cba9e&bu=3D43210693952&exe=3D15083&ext=3D38992&sojTa=
gs=3Dexe=3Dexe,ext=3Dext,bu=3Dbu" alt=3D"" style=3D"border:0; height:1;"/><=
/td>
</tr>
</table>
</td>
</tr>
</table>   <table id=3D"area4Container" width=3D"100%" border=3D"0" cellpad=
ding=3D"0" cellspacing=3D"0" align=3D"center" style=3D"border-collapse: col=
lapse !important; border-spacing: 0 !important; border: none; background-co=
lor:#f9f9f9">
<tr>
<td width=3D"100%" valign=3D"top" style=3D"border-collapse: collapse !impor=
tant; border-spacing: 0 !important; border: none;">
<table width=3D"600" cellspacing=3D"0" cellpadding=3D"0" border=3D"0" bgcol=
or=3D"#f9f9f9" align=3D"center" style=3D"border-collapse: collapse !importa=
nt; border-spacing: 0 !important; border: none;" class=3D"device-width">
<tbody>
<tr>
<td valign=3D"top" style=3D"border-collapse: collapse !important; border-sp=
acing: 0 !important; padding: 0;">
<h1 align=3D"left" class=3D"mobile-dealmaker-headline" style=3D"font-family=
: Helvetica, Arial, sans-serif; font-weight: 200; line-height: 29px; color:=
 #333333; text-align: left; font-size: 24px; margin: 0;">
Daccordi, Worldwide: <a href=3D'http://rover.ebay.com/rover/0/e11021.m3197.=
l1150/7?euid=3Dd9f42b5e860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp=
%3A%2F%2Fwww.ebay.com.au%2Fsch%2FCycling-%2F7294%2Fi.html%3FLH_PrefLoc%3D2%=
26_sop%3D10%26_fln%3D1%26_nkw%3DDaccordi%26_trksid%3Dm194%26ssPageName%3DST=
RK%253AMEFSRCHX%253ASRCH&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ext=3D=
ext,bu=3Dbu' style=3D'text-decoration:none'>2 new</a> matches today
</h1>
</td>
</tr>
</tbody>
</table>
</td>
</tr>
</table>  <table width=3D"100%" border=3D"0" cellpadding=3D"0" cellspacing=
=3D"0" align=3D"center" style=3D"border-collapse: collapse !important; bord=
er-spacing: 0 !important; border: none;">
<tr>
<td width=3D"100%" valign=3D"top" bgcolor=3D"#f9f9f9" style=3D"border-colla=
pse: collapse !important; border-spacing: 0 !important; border: none;">
<table width=3D"600" border=3D"0" align=3D"center" cellspacing=3D"0" cellpa=
dding=3D"0" style=3D"border-collapse: collapse !important; border-spacing: =
0 !important; border: none;" class=3D"device-width">
<tbody>
<tr>
<td valign=3D"top" style=3D"border-collapse: collapse !important; border-sp=
acing: 0 !important; border: none; padding: 0; margin: 0;">
<div align=3D"left" border=3D"0" cellspacing=3D"0" cellpadding=3D"0" width=
=3D"146" style=3D"border-collapse: separate !important; border-spacing: 0 !=
important; border: none; float:left; display:inline;">
<table width=3D"146" border=3D"0" align=3D"left" cellspacing=3D"0" cellpadd=
ing=3D"0" style=3D"border-collapse: collapse !important; border-spacing: 0 =
!important; border: none; color: #333333">
<tr>
<td class=3D"mobile-multi-item-left-image" valign=3D"top" style=3D"border-c=
ollapse: collapse !important; border-spacing: 0 !important; padding: 12px 1=
2px 12px 0; border: none;">
<table width=3D"100%" border=3D"0" cellspacing=3D"0" cellpadding=3D"0" styl=
e=3D"border-collapse: collapse !important; border-spacing: 0 !important; bo=
rder: none;">
<tr>
<td style=3D"border-collapse: collapse !important; border-spacing: 0 !impor=
tant; border: none; padding: 0; margin: 0;">
<table width=3D"132" height=3D"132" cellspacing=3D"0" cellpadding=3D"0" sty=
le=3D"border-collapse: collapse !important; border-spacing: 0 !important; p=
adding: 0; border: none;">
<tbody>
<tr>
<td width=3D"132" valign=3D"center" height=3D"132" align=3D"center" style=
=3D"max-width: 132px; border: 1px solid #dddddd;">
<a href=3D"http://rover.ebay.com/rover/0/e11021.m43.l1120/7?euid=3Dd9f42b5e=
860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Fwww.ebay.com.a=
u%2Fulk%2Fitm%2F391655221238&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ex=
t=3Dext,bu=3Dbu">
<span style=3D"display: block; outline: none; text-decoration: none; -ms-in=
terpolation-mode: bicubic; border-radius: 3px; margin: 0; ">
<img border=3D"0" src=3D"http://i.ebayimg.com/images/g/dxcAAOSwJ7RYVbhB/s-b=
132x132.jpg" style=3D"max-width:100%; display: block; outline: none; text-d=
ecoration: none; -ms-interpolation-mode: bicubic; margin: 0; border: none;"=
 />
</span>
</a>
</td>
</tr>
</tbody>
</table>
</td>
</tr>
<tr>
<td valign=3D"top" style=3D"max-width: 132px; border-collapse: collapse !im=
portant; border-spacing: 0 !important; padding: 12px 0 0; border: none;">
<h3 align=3D"left" style=3D"font-family: Helvetica, Arial, sans-serif; font=
-weight: normal; line-height: normal; color: #333333; text-align: left; fon=
t-size: 12px; margin: 0 0 10px; word-break:break-all; height:31px;">
<a style=3D"text-decoration: none; color: #0654ba;" href=3D"http://rover.eb=
ay.com/rover/0/e11021.m43.l3160/7?euid=3Dd9f42b5e860b4eabb98195c2888cba9e&b=
u=3D43210693952&loc=3Dhttp%3A%2F%2Fwww.ebay.com.au%2Fulk%2Fitm%2F3916552212=
38&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ext=3Dext,bu=3Dbu">
Daccordi 50th anniversary edition with...
</a>
</h3>
</td>
</tr>
<tr>
<td align=3D"left" style=3D"border-collapse: collapse !important; border-sp=
acing: 0 !important; font-family: Helvetica, Arial, sans-serif; text-align:=
 left; font-size: 12px; font-weight: bold; border: none; padding-bottom: 8p=
x;">
Buy it now: US $5,950.00
</td>
</tr>
<tr>
<td align=3D"left" style=3D"border-collapse: collapse !important; border-sp=
acing: 0 !important; font-family: Helvetica, Arial, sans-serif; text-align:=
 left; font-size: 12px; color: #E53238; font-weight: normal; border: none; =
padding: 0; margin: 0;">
100% positive feedback
</td>
</tr>
</table>
</td>
</tr>
</table>
<table width=3D"146" border=3D"0" align=3D"left" cellspacing=3D"0" cellpadd=
ing=3D"0" style=3D"border-collapse: collapse !important; border-spacing: 0 =
!important; border: none; color: #333333">
<tr>
<td class=3D"mobile-multi-item-right-image" valign=3D"top" style=3D"border-=
collapse: collapse !important; border-spacing: 0 !important; padding: 12px =
12px 12px 0; border: none;">
<table width=3D"100%" border=3D"0" cellspacing=3D"0" cellpadding=3D"0" styl=
e=3D"border-collapse: collapse !important; border-spacing: 0 !important; bo=
rder: none;">
<tr>
<td style=3D"border-collapse: collapse !important; border-spacing: 0 !impor=
tant; border: none; padding: 0; margin: 0;">
<table width=3D"132" height=3D"132" cellspacing=3D"0" cellpadding=3D"0" sty=
le=3D"border-collapse: collapse !important; border-spacing: 0 !important; p=
adding: 0; border: none;">
<tbody>
<tr>
<td width=3D"132" valign=3D"center" height=3D"132" align=3D"center" style=
=3D"max-width: 132px; border: 1px solid #dddddd;">
<a href=3D"http://rover.ebay.com/rover/0/e11021.m43.l1120/7?euid=3Dd9f42b5e=
860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Fwww.ebay.com.a=
u%2Fulk%2Fitm%2F132037720927&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ex=
t=3Dext,bu=3Dbu">
<span style=3D"display: block; outline: none; text-decoration: none; -ms-in=
terpolation-mode: bicubic; border-radius: 3px; margin: 0; ">
<img border=3D"0" src=3D"http://i.ebayimg.com/images/g/C3cAAOSwj85YOiHQ/s-b=
132x132.jpg" style=3D"max-width:100%; display: block; outline: none; text-d=
ecoration: none; -ms-interpolation-mode: bicubic; margin: 0; border: none;"=
 />
</span>
</a>
</td>
</tr>
</tbody>
</table>
</td>
</tr>
<tr>
<td valign=3D"top" style=3D"max-width: 132px; border-collapse: collapse !im=
portant; border-spacing: 0 !important; padding: 12px 0 0; border: none;">
<h3 align=3D"left" style=3D"font-family: Helvetica, Arial, sans-serif; font=
-weight: normal; line-height: normal; color: #333333; text-align: left; fon=
t-size: 12px; margin: 0 0 10px; word-break:break-all; height:31px;">
<a style=3D"text-decoration: none; color: #0654ba;" href=3D"http://rover.eb=
ay.com/rover/0/e11021.m43.l3160/7?euid=3Dd9f42b5e860b4eabb98195c2888cba9e&b=
u=3D43210693952&loc=3Dhttp%3A%2F%2Fwww.ebay.com.au%2Fulk%2Fitm%2F1320377209=
27&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ext=3Dext,bu=3Dbu">
Daccordi Griffe Campagnolo Croce D'Aune...
</a>
</h3>
</td>
</tr>
<tr>
<td align=3D"left" style=3D"border-collapse: collapse !important; border-sp=
acing: 0 !important; font-family: Helvetica, Arial, sans-serif; text-align:=
 left; font-size: 12px; font-weight: bold; border: none; padding-bottom: 8p=
x;">
Buy it now: US $1,750.00
</td>
</tr>
<tr>
<td align=3D"left" style=3D"border-collapse: collapse !important; border-sp=
acing: 0 !important; font-family: Helvetica, Arial, sans-serif; text-align:=
 left; font-size: 12px; color: #E53238; font-weight: normal; border: none; =
padding: 0; margin: 0;">
100% positive feedback
</td>
</tr>
</table>
</td>
</tr>
</table>
</div>
</td>
</tr>
</tbody>
</table>
</td>
</tr>
</table> <table id=3D"area5Container" width=3D"100%" border=3D"0" cellpaddi=
ng=3D"0" cellspacing=3D"0" align=3D"center" style=3D"border-collapse: colla=
pse !important; border-spacing: 0 !important; border: none; background-colo=
r:#f9f9f9">
<tr>
<td>
<table width=3D"600" class=3D"device-width" border=3D"0" cellpadding=3D"0" =
cellspacing=3D"0" align=3D"center" bgcolor=3D"#f9f9f9" style=3D"border-coll=
apse: collapse !important; border-spacing: 0 !important; border: none;">
<tr>
<td valign=3D"top" class=3D"cta-block-2" style=3D"border-collapse: collapse=
 !important; border-spacing: 0 !important; border: none;">
<table align=3D"left" cellpadding=3D"0" cellspacing=3D"0" border=3D"0" styl=
e=3D"border-collapse: collapse !important; border-spacing: 0 !important; bo=
rder: none; padding: 10px 0">
<tr><td>
<table align=3D"left" cellpadding=3D"0" cellspacing=3D"0" border=3D"0" clas=
s=3D"mobile-full-width" style=3D"max-width: 320px; border-collapse: collaps=
e !important; border-spacing: 0 !important;">
<tr>
<td width=3D"292" valign=3D"top" class=3D"center mobile-dealmaker-CTA1" ali=
gn=3D"center" bgcolor=3D"#0654BA" style=3D"min-width: 290px;border-collapse=
: collapse !important; border-spacing: 0 !important; font-size: 16px; line-=
height: normal;background-color: 0654BA; padding: 11px 17px; ">
<a href=3D"http://rover.ebay.com/rover/0/e11021.m4442.l1150/7?euid=3Dd9f42b=
5e860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Fwww.ebay.com=
.au%2Fsch%2FCycling-%2F7294%2Fi.html%3FLH_PrefLoc%3D2%26_sop%3D10%26_fln%3D=
1%26_nkw%3DDaccordi%26_trksid%3Dm194%26ssPageName%3DSTRK%253AMEFSRCHX%253AS=
RCH&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ext=3Dext,bu=3Dbu" style=3D=
"text-decoration: none; color: #ffffff; font-size: 16px; line-height: 18px;=
 font-weight: 200; font-family: Helvetica, Arial, sans-serif; padding: 11px=
 17px;"> View all results</a>
</td>
</tr>
</table>
</td>
<td style=3D"border-collapse: collapse !important;
border-spacing: 0; !important; padding: 0"><img class=3D"collapse" src=3D"h=
ttp://p.ebaystatic.com/aw/email/Welcome_Day_0/spacer.gif" width=3D"5" heigh=
t=3D"1" alt=3D"" border=3D"0" style=3D"display:block; width: 5px !important=
"></td>
</tr>
<!--[if ! gte mso 9]>
<tr>
<td style=3D"border-collapse: collapse !important;
border-spacing: 0; !important; padding: 0"><img src=3D"http://p.ebaystatic.=
com/aw/email/Welcome_Day_0/spacer.gif" width=3D"1" height=3D"5" alt=3D"" bo=
rder=3D"0" style=3D"display:block; height: 5px !important"></td>
</tr>
<![endif]-->
</table>
<table align=3D"left" cellpadding=3D"0" cellspacing=3D"0" border=3D"0" styl=
e=3D"border-collapse: collapse !important; border-spacing: 0 !important; bo=
rder: none; padding: 10px 0">
<tr><td>
<table align=3D"left" cellpadding=3D"0" cellspacing=3D"0" border=3D"0" clas=
s=3D"mobile-full-width" style=3D"max-width: 320px; border-collapse: collaps=
e !important; border-spacing: 0 !important; border: 1px solid #dddddd;borde=
r-radius: 3px;">
<tr>
<td width=3D"290" valign=3D"top" class=3D"center mobile-dealmaker-CTA1" ali=
gn=3D"center" bgcolor=3D"#ffffff" style=3D"min-width: 290px; border-collaps=
e: collapse !important; border-spacing: 0 !important; font-size: 16px; line=
-height: normal;background-color: ffffff; padding: 10px 17px; ">
<a href=3D"http://rover.ebay.com/rover/0/e11021.m4442.l1179/7?euid=3Dd9f42b=
5e860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Fwww.ebay.com=
.au%2Fsch%2FCycling-%2F7294%2Fi.html%3FLH_PrefLoc%3D2%26_sop%3D10%26_fln%3D=
1%26_nkw%3DDaccordi%26_trksid%3Dm194%26ssPageName%3DSTRK%253AMEFSRCHX%253AS=
RCH%26replaceid%3D19105329025&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,e=
xt=3Dext,bu=3Dbu" style=3D"text-decoration: none; color: #0654BA; font-size=
: 16px; line-height: 18px; font-weight: 200; font-family: Helvetica, Arial,=
 sans-serif; padding: 10px 17px;">Refine this search</a>
</td>
</tr>
</table>
</td>
<td style=3D"border-collapse: collapse !important;
border-spacing: 0; !important; padding: 0"><img class=3D"collapse" src=3D"h=
ttp://p.ebaystatic.com/aw/email/Welcome_Day_0/spacer.gif" width=3D"5" heigh=
t=3D"1" alt=3D"" border=3D"0" style=3D"display:block; width: 5px !important=
"></td>
</tr>
<!--[if ! gte mso 9]>
<tr>
<td style=3D"border-collapse: collapse !important;
border-spacing: 0; !important; padding: 0"><img src=3D"http://p.ebaystatic.=
com/aw/email/Welcome_Day_0/spacer.gif" width=3D"1" height=3D"5" alt=3D"" bo=
rder=3D"0" style=3D"display:block; height: 5px !important"></td>
</tr>
<![endif]-->
</table>
</td>
</tr>
<tr>
<td valign=3D"top" class=3D"cta-block-3" style=3D"border-collapse: collapse=
 !important; border-spacing: 0 !important; padding: 0 0 8px 0px; border: no=
ne;">
<table width=3D"100%" align=3D"left" cellpadding=3D"0" cellspacing=3D"0" bo=
rder=3D"0" style=3D"border-collapse: collapse !important; border-spacing: 0=
 !important; border: none;">
<tr>
<td width=3D"100%" valign=3D"top" class=3D"center" align=3D"center" style=
=3D"border-collapse: collapse !important; border-spacing: 0 !important; fon=
t-size: 14px; line-height: normal; padding: 0px 17px;">
<a href=3D"http://rover.ebay.com/rover/0/e11021.m4442.l1142/7?euid=3Dd9f42b=
5e860b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Fcontact.ebay=
.com.au%2Fws%2FeBayISAPI.dll%3FUnsubscribeEmailFavoriteSearch%26%26query%3D=
3139313035333239303235-0db6b1b2ceaf88ebfc5edb9514cc5a36&exe=3D15083&ext=3D3=
8992&sojTags=3Dexe=3Dexe,ext=3Dext,bu=3Dbu" style=3D"text-decoration: none;=
 color: #0654BA; font-size: 14px; line-height: 18px; font-weight: normal; f=
ont-family: Helvetica, Arial, sans-serif;"> Disable emails for this search<=
/a>
</td>
</tr>
</table>
</td>
</tr>
</table>
</td>
</tr>
</table> <table id=3D"area8Container" width=3D"100%" border=3D"0" cellpaddi=
ng=3D"0" cellspacing=3D"0" align=3D"center" style=3D"border-collapse: colla=
pse !important; border-spacing: 0 !important; border: none; border-top: sol=
id 1px #dddddd; background-color: #ffffff"><tr><td style=3D"font-size:0px; =
line-height:0px" height=3D"1">&nbsp;</td></tr></table> <table id=3D"area11C=
ontainer" class=3D"whiteSection" width=3D"100%" border=3D"0" cellpadding=3D=
"0" cellspacing=3D"0" align=3D"center" style=3D"border-collapse: collapse !=
important; border-spacing: 0 !important; border: none; background-color: #f=
fffff">
<tr>
<td width=3D"100%" valign=3D"top" style=3D"border-collapse: collapse !impor=
tant; border-spacing: 0 !important; border: none;">
<table width=3D"600" class=3D"device-width" border=3D"0" cellpadding=3D"0" =
cellspacing=3D"0" align=3D"center" style=3D"border-collapse: collapse !impo=
rtant; border-spacing: 0 !important; border: none;">
<tr>
<td class=3D"ebay-footer-block" style=3D"border-collapse: collapse !importa=
nt; border-spacing: 0 !important; padding: 20px 0 60px; border: none;">
<div id=3D"ReferenceId">
<p style=3D"font-family: Helvetica, Arial, sans-serif; font-weight: normal;=
 line-height: normal; color: #888888; text-align: left; font-size: 11px; ma=
rgin: 0 0 10px;" align=3D"left"><strong>
Email reference id: [#d9f42b5e860b4eabb98195c2888cba9e#]
</strong></p></div>
<p style=3D"font-family: Helvetica, Arial, sans-serif; font-weight: normal;=
 line-height: normal; color: #888888; text-align: left; font-size: 11px; ma=
rgin: 0 0 10px;" align=3D"left">
We don't check this mailbox, so please don't reply to this message. If you =
have a question, go to <a style=3D"text-decoration: none; color: #555555;" =
href=3D"http://rover.ebay.com/rover/0/e11021.m1852.l6369/7?euid=3Dd9f42b5e8=
60b4eabb98195c2888cba9e&bu=3D43210693952&loc=3Dhttp%3A%2F%2Focsnext.ebay.co=
m.au%2Focs%2Fhome&exe=3D15083&ext=3D38992&sojTags=3Dexe=3Dexe,ext=3Dext,bu=
=3Dbu" target=3D"_blank">Help & Contact</a>.
</p>
<p style=3D"font-family: Helvetica, Arial, sans-serif; font-weight: normal;=
 line-height: normal; color: #888888; text-align: left; font-size: 11px; ma=
rgin: 0 0 10px;" align=3D"left">
&copy;2016 eBay Inc., eBay International AG Helvetiastrasse 15/17 - P.O. Bo=
x 133, 3000 Bern 6, Switzerland
</p>
</td>
</tr>
</table>
</td>
</tr>
</table>         </div>
    </center></body>
</html>

""";

    public static string HTML_BODY2_EXPECTED = "Buy It Now from US $1,750.00 to US $5,950.00. eBay Daccordi, Worldwide: 2 new matches today Daccordi 50th anniversary edition with... Buy it now: US $5,950.00 100% positive feedback Daccordi Griffe Campagnolo Croce D'Aune... Buy it now: US $1,750.00 100% positive feedback View all results Refine this search Disable emails for this search Email reference id: [#d9f42b5e860b4eabb98195c2888cba9e#] We don't check this mailbox, so please don't reply to this message. If you have a question, go to Help & Contact. ©2016 eBay Inc., eBay International AG Helvetiastrasse 15/17 - P.O. Box 133, 3000 Bern 6, Switzerland";
}
