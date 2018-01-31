/*
 * Copyright 2016-2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.MessageTest : Gee.TestCase {

    public MessageTest() {
        base("Geary.RFC822.MessageTest");
        add_test("basic_message_from_buffer", basic_message_from_buffer);
        add_test("encoded_recipient", encoded_recipient);
        add_test("duplicate_mailbox", duplicate_mailbox);
        add_test("duplicate_message_id", duplicate_message_id);
        add_test("get_preview", get_preview);
    }

    public void basic_message_from_buffer() {
        Message? basic = null;
        try {
            basic = string_to_message(BASIC_MESSAGE);
        } catch (Error err) {
            assert_no_error(err);
        }
        assert_data(basic.subject, "Re: Saying Hello");
        assert_addresses(basic.from, "Mary Smith <mary@example.net>");
        assert_address(basic.sender, "Mary Smith Sender <mary@example.net>");
        assert_addresses(basic.reply_to, "\"Mary Smith: Personal Account\" <smith@home.example>");
        assert_addresses(basic.to, "John Doe <jdoe@machine.example>");
        assert_addresses(basic.cc, "John Doe CC <jdoe@machine.example>");
        assert_addresses(basic.bcc, "John Doe BCC <jdoe@machine.example>");
        //assert_data(basic.message_id, "<3456@example.net>");
        assert_message_id_list(basic.in_reply_to, "<1234@local.machine.example>");
        assert_message_id_list(basic.references, "<1234@local.machine.example>");
        assert_data(basic.date, "Fri, 21 Nov 1997 10:01:10 -0600");
        assert(basic.mailer == "Geary Test Suite 1.0");
    }

    public void encoded_recipient() {
        Message? enc = null;
        try {
            enc = string_to_message(ENCODED_TO);
        } catch (Error err) {
            assert_no_error(err);
        }

        // Courtesy Mailsploit https://www.mailsploit.com
        assert(enc.to[0].name == "potus@whitehouse.gov <test>");
    }

    public void duplicate_mailbox() {
        Message? dup = null;
        try {
            dup = string_to_message(DUPLICATE_TO);
        } catch (Error err) {
            assert_no_error(err);
        }

        assert(dup.to.size == 2);
        assert_addresses(
            dup.to, "John Doe 1 <jdoe1@machine.example>, John Doe 2 <jdoe2@machine.example>"
        );
    }

    public void duplicate_message_id() {
        Message? dup = null;
        try {
            dup = string_to_message(DUPLICATE_REFERENCES);
        } catch (Error err) {
            assert_no_error(err);
        }

        assert(dup.references.list.size == 2);
        assert_message_id_list(
            dup.references, "<1234@local.machine.example> <5678@local.machine.example>"
        );
    }

    public void get_preview() {
        try {
            Message multipart_signed = string_to_message(MULTIPART_SIGNED_MESSAGE_TEXT);
            assert(multipart_signed.get_preview() == MULTIPART_SIGNED_MESSAGE_PREVIEW);
        } catch (Error err) {
            assert_no_error(err);
        }
    }

    private Message string_to_message(string message_text) throws Error {
        return new Message.from_buffer(
            new Geary.Memory.StringBuffer(message_text)
        );
    }

    private void assert_data(Geary.MessageData.AbstractMessageData? data, string expected) {
        assert(data != null);
        assert(data.to_string() == expected);
    }

    private void assert_address(Geary.RFC822.MailboxAddress? address, string expected) {
        assert(address != null);
        assert(address.to_rfc822_string() == expected);
    }

    private void assert_addresses(Geary.RFC822.MailboxAddresses? addresses, string expected) {
        assert(addresses != null);
        assert(addresses.to_rfc822_string() == expected);
    }

    private void assert_message_id_list(Geary.RFC822.MessageIDList? ids, string expected) {
        assert(ids != null);
        assert(ids.to_rfc822_string() == expected);
    }

    private static string BASIC_MESSAGE = "From: Mary Smith <mary@example.net>\r\nSender: Mary Smith Sender <mary@example.net>\r\nTo: John Doe <jdoe@machine.example>\r\nCC: John Doe CC <jdoe@machine.example>\r\nBCC: John Doe BCC <jdoe@machine.example>\r\nReply-To: \"Mary Smith: Personal Account\" <smith@home.example>\r\nSubject: Re: Saying Hello\r\nDate: Fri, 21 Nov 1997 10:01:10 -0600\r\nMessage-ID: <3456@example.net>\r\nIn-Reply-To: <1234@local.machine.example>\r\nReferences: <1234@local.machine.example>\r\nX-Mailer: Geary Test Suite 1.0\r\n\r\nThis is a reply to your hello.\r\n\r\n";

    // Courtesy Mailsploit https://www.mailsploit.com
    private static string ENCODED_TO = "From: Mary Smith <mary@example.net>\r\nTo: =?utf-8?b?cG90dXNAd2hpdGVob3VzZS5nb3YiIDx0ZXN0Pg==?= <jdoe@machine.example>\r\nSubject: Re: Saying Hello\r\nDate: Fri, 21 Nov 1997 10:01:10 -0600\r\n\r\nThis is a reply to your hello.\r\n\r\n";

    private static string DUPLICATE_TO = "From: Mary Smith <mary@example.net>\r\nTo: John Doe 1 <jdoe1@machine.example>\r\nTo: John Doe 2 <jdoe2@machine.example>\r\nSubject: Re: Saying Hello\r\nDate: Fri, 21 Nov 1997 10:01:10 -0600\r\n\r\nThis is a reply to your hello.\r\n\r\n";

    private static string DUPLICATE_REFERENCES = "From: Mary Smith <mary@example.net>\r\nTo: John Doe <jdoe@machine.example>\r\nReferences: <1234@local.machine.example>\r\nReferences: <5678@local.machine.example>\r\nSubject: Re: Saying Hello\r\nDate: Fri, 21 Nov 1997 10:01:10 -0600\r\n\r\nThis is a reply to your hello.\r\n\r\n";

    private static string MULTIPART_SIGNED_MESSAGE_TEXT = "Return-Path: <ubuntu-security-announce-bounces@lists.ubuntu.com>\r\nReceived: from mogul.quuxo.net ([unix socket])\r\n	 by mogul (Cyrus v2.4.12-Debian-2.4.12-2) with LMTPA;\r\n	 Wed, 21 Dec 2016 06:54:03 +1030\r\nX-Sieve: CMU Sieve 2.4\r\nReceived: from huckleberry.canonical.com (huckleberry.canonical.com [91.189.94.19])\r\n	by mogul.quuxo.net (8.14.4/8.14.4/Debian-2ubuntu2.1) with ESMTP id uBKKNtpt026727\r\n	for <mike@vee.net>; Wed, 21 Dec 2016 06:53:57 +1030\r\nReceived: from localhost ([127.0.0.1] helo=huckleberry.canonical.com)\r\n	by huckleberry.canonical.com with esmtp (Exim 4.76)\r\n	(envelope-from <ubuntu-security-announce-bounces@lists.ubuntu.com>)\r\n	id 1cJQwM-0003Xk-IO; Tue, 20 Dec 2016 20:23:14 +0000\r\nReceived: from 208-151-246-43.dq1sn.easystreet.com ([208.151.246.43]\r\n helo=lizaveta.nxnw.org)\r\n by huckleberry.canonical.com with esmtps (TLS1.0:DHE_RSA_AES_256_CBC_SHA1:32)\r\n (Exim 4.76) (envelope-from <steve.beattie@canonical.com>)\r\n id 1cJQin-0000t2-G6\r\n for ubuntu-security-announce@lists.ubuntu.com; Tue, 20 Dec 2016 20:09:14 +0000\r\nReceived: from kryten.nxnw.org (kryten.nxnw.org [10.19.96.254])\r\n (using TLSv1.2 with cipher ECDHE-RSA-AES256-GCM-SHA384 (256/256 bits))\r\n (Client CN \"kryten.int.wirex.com\", Issuer \"nxnw.org\" (not verified))\r\n by lizaveta.nxnw.org (Postfix) with ESMTPS id DD8C360941\r\n for <ubuntu-security-announce@lists.ubuntu.com>;\r\n Tue, 20 Dec 2016 12:09:06 -0800 (PST)\r\nReceived: by kryten.nxnw.org (Postfix, from userid 1000)\r\n id 84341342F6C; Tue, 20 Dec 2016 12:09:06 -0800 (PST)\r\nDate: Tue, 20 Dec 2016 12:09:06 -0800\r\nFrom: Steve Beattie <steve.beattie@canonical.com>\r\nTo: ubuntu-security-announce@lists.ubuntu.com\r\nSubject: [USN-3159-1] Linux kernel vulnerability\r\nMessage-ID: <20161220200906.GF8251@nxnw.org>\r\nMail-Followup-To: Ubuntu Security <security@ubuntu.com>\r\nMIME-Version: 1.0\r\nUser-Agent: Mutt/1.5.24 (2015-08-30)\r\nX-Mailman-Approved-At: Tue, 20 Dec 2016 20:23:12 +0000\r\nX-BeenThere: ubuntu-security-announce@lists.ubuntu.com\r\nX-Mailman-Version: 2.1.14\r\nPrecedence: list\r\nReply-To: ubuntu-users@lists.ubuntu.com, Ubuntu Security <security@ubuntu.com>\r\nList-Id: Ubuntu Security Announcements\r\n <ubuntu-security-announce.lists.ubuntu.com>\r\nList-Unsubscribe: <https://lists.ubuntu.com/mailman/options/ubuntu-security-announce>, \r\n <mailto:ubuntu-security-announce-request@lists.ubuntu.com?subject=unsubscribe>\r\nList-Archive: <https://lists.ubuntu.com/archives/ubuntu-security-announce>\r\nList-Post: <mailto:ubuntu-security-announce@lists.ubuntu.com>\r\nList-Help: <mailto:ubuntu-security-announce-request@lists.ubuntu.com?subject=help>\r\nList-Subscribe: <https://lists.ubuntu.com/mailman/listinfo/ubuntu-security-announce>, \r\n <mailto:ubuntu-security-announce-request@lists.ubuntu.com?subject=subscribe>\r\nContent-Type: multipart/mixed; boundary=\"===============7564301068935298617==\"\r\nErrors-To: ubuntu-security-announce-bounces@lists.ubuntu.com\r\nSender: ubuntu-security-announce-bounces@lists.ubuntu.com\r\nX-Greylist: Sender IP whitelisted by DNSRBL, not delayed by milter-greylist-4.3.9 (mogul.quuxo.net [203.18.245.241]); Wed, 21 Dec 2016 06:53:57 +1030 (ACDT)\r\nX-Virus-Scanned: clamav-milter 0.99.2 at mogul\r\nX-Virus-Status: Clean\r\nX-Spam-Status: No, score=-4.2 required=5.0 tests=BAYES_00,RCVD_IN_DNSWL_MED\r\n	autolearn=ham version=3.3.2\r\nX-Spam-Checker-Version: SpamAssassin 3.3.2 (2011-06-06) on mogul.quuxo.net\r\n\r\n\r\n--===============7564301068935298617==\r\nContent-Type: multipart/signed; micalg=pgp-sha512;\r\n	protocol=\"application/pgp-signature\"; boundary=\"O98KdSgI27dgYlM5\"\r\nContent-Disposition: inline\r\n\r\n\r\n--O98KdSgI27dgYlM5\r\nContent-Type: text/plain; charset=us-ascii\r\nContent-Disposition: inline\r\n\r\n==========================================================================\r\nUbuntu Security Notice USN-3159-1\r\nDecember 20, 2016\r\n\r\nlinux vulnerability\r\n==========================================================================\r\n\r\nA security issue affects these releases of Ubuntu and its derivatives:\r\n\r\n- Ubuntu 12.04 LTS\r\n\r\nSummary:\r\n\r\nThe system could be made to expose sensitive information.\r\n\r\nSoftware Description:\r\n- linux: Linux kernel\r\n\r\nDetails:\r\n\r\nIt was discovered that a race condition existed in the procfs\r\nenviron_read function in the Linux kernel, leading to an integer\r\nunderflow. A local attacker could use this to expose sensitive\r\ninformation (kernel memory).\r\n\r\nUpdate instructions:\r\n\r\nThe problem can be corrected by updating your system to the following\r\npackage versions:\r\n\r\nUbuntu 12.04 LTS:\r\n  linux-image-3.2.0-119-generic   3.2.0-119.162\r\n  linux-image-3.2.0-119-generic-pae  3.2.0-119.162\r\n  linux-image-3.2.0-119-highbank  3.2.0-119.162\r\n  linux-image-3.2.0-119-omap      3.2.0-119.162\r\n  linux-image-3.2.0-119-powerpc-smp  3.2.0-119.162\r\n  linux-image-3.2.0-119-powerpc64-smp  3.2.0-119.162\r\n  linux-image-3.2.0-119-virtual   3.2.0-119.162\r\n  linux-image-generic             3.2.0.119.134\r\n  linux-image-generic-pae         3.2.0.119.134\r\n  linux-image-highbank            3.2.0.119.134\r\n  linux-image-omap                3.2.0.119.134\r\n  linux-image-powerpc-smp         3.2.0.119.134\r\n  linux-image-powerpc64-smp       3.2.0.119.134\r\n  linux-image-virtual             3.2.0.119.134\r\n\r\nAfter a standard system update you need to reboot your computer to make\r\nall the necessary changes.\r\n\r\nATTENTION: Due to an unavoidable ABI change the kernel updates have\r\nbeen given a new version number, which requires you to recompile and\r\nreinstall all third party kernel modules you might have installed.\r\nUnless you manually uninstalled the standard kernel metapackages\r\n(e.g. linux-generic, linux-generic-lts-RELEASE, linux-virtual,\r\nlinux-powerpc), a standard system upgrade will automatically perform\r\nthis as well.\r\n\r\nReferences:\r\n  http://www.ubuntu.com/usn/usn-3159-1\r\n  CVE-2016-7916\r\n\r\nPackage Information:\r\n  https://launchpad.net/ubuntu/+source/linux/3.2.0-119.162\r\n\r\n\r\n--O98KdSgI27dgYlM5\r\nContent-Type: application/pgp-signature; name=\"signature.asc\"\r\n\r\n-----BEGIN PGP SIGNATURE-----\r\nVersion: GnuPG v1\r\n\r\niQIcBAEBCgAGBQJYWY/iAAoJEC8Jno0AXoH0gKUQAJ7UOWV591M8K+HGXHI3BVJi\r\n75LCUSBRrV2NZTpc32ZMCsssb4TSqQinzczQfWSNtlLsgucKTLdCYGJvbXYxd32z\r\nBzHHHH9D8EDC6X4Olx0byiDBTX76kVBVUjxsKJ1zkYBFeMZ6tx9Tmgsl7Rdr26lP\r\n9oe3nBadkP0vM7j/dG1913MdzOlFc/2YOnGRK6QKzy1HhM74XMQTzvj9Nsbgs8ea\r\nZFTzWgDiUXi9SbBDLmwkY2uFJ+zreIH/vRjZHZ5ofJz9ed91HDhMB7CmRzn4JG/b\r\nSPAmTk0IRzWVBWglb0hPA8NN194ijeQFa6OJt94+EIMYuIasjsi8zGr+o1yxM5aY\r\ngTiDLzrQVWfddcZWmoCw8WWVbHAjMW60ehAs+y6ly0tBAn7wailXFRDFir1Vt4i2\r\n1WRTnJR2JebfQN4YeJ7CAiw34+PO8+vi8qHcRqMGkRu5IYdBy8AvBucVO923jIIy\r\nJBRTVkZqacRVp4PLx7vrOXX02z7y38iQcP2QSeapMoQjViYOVSMYhycO9zqGe3Tj\r\nAHMqp2HGj1uPp+3mM/yRBaE1X1j7lzjsKO1XZwjMUIYcFmAAsg2Gwi5S0FhhS+cD\r\nulCZ0A+r4wZ/1K6cZ2ZCEQoAZyMovwiVLNP+4q7pHhcQGTYAvCEgPksktQwD3YOe\r\nnSj5HG2dTMTOHDjVGSVV\r\n=qUGf\r\n-----END PGP SIGNATURE-----\r\n\r\n--O98KdSgI27dgYlM5--\r\n\r\n\r\n--===============7564301068935298617==\r\nContent-Type: text/plain; charset=\"us-ascii\"\r\nMIME-Version: 1.0\r\nContent-Transfer-Encoding: 7bit\r\nContent-Disposition: inline\r\n\r\n-- \r\nubuntu-security-announce mailing list\r\nubuntu-security-announce@lists.ubuntu.com\r\nModify settings or unsubscribe at: https://lists.ubuntu.com/mailman/listinfo/ubuntu-security-announce\r\n\r\n--===============7564301068935298617==--\r\n";
    private static string MULTIPART_SIGNED_MESSAGE_PREVIEW = "Ubuntu Security Notice USN-3159-1 December 20, 2016 linux vulnerability A security issue affects these releases of Ubuntu and its derivatives: - Ubuntu 12.04 LTS Summary: The system could be made to expose sensitive information. Software Description: - linux: Linux kernel Details: It was discovered that a race condition existed in the procfs environ_read function in the Linux kernel, leading to an integer underflow. A local attacker could use this to expose sensitive information (kernel memory). Update instructions: The problem can be corrected by updating your system to the following package versions: Ubuntu 12.04 LTS: linux-image-3.2.0-119-generic 3.2.0-119.162 linux-image-3.2.0-119-generic-pae 3.2.0-119.162 linux-image-3.2.0-119-highbank 3.2.0-119.162 linux-image-3.2.0-119-omap 3.2.0-119.162 linux-image-3.2.0-119-powerpc-smp 3.2.0-119.162 linux-image-3.2.0-119-powerpc64-smp 3.2.0-119.162 linux-image-3.2.0-119-virtual 3.2.0-119.162 linux-image-generic 3.2.0.119.134 linux-image-generic-pae 3.2.0.119.134 linux-image-highbank 3.2.0.119.134 linux-image-omap 3.2.0.119.134 linux-image-powerpc-smp 3.2.0.119.134 linux-image-powerpc64-smp 3.2.0.119.134 linux-image-virtual 3.2.0.119.134 After a standard system update you need to reboot your computer to make all the necessary changes. ATTENTION: Due to an unavoidable ABI change the kernel updates have been given a new version number, which requires you to recompile and reinstall all third party kernel modules you might have installed. Unless you manually uninstalled the standard kernel metapackages (e.g. linux-generic, linux-generic-lts-RELEASE, linux-virtual, linux-powerpc), a standard system upgrade will automatically perform this as well. References: http://www.ubuntu.com/usn/usn-3159-1 CVE-2016-7916 Package Information: https://launchpad.net/ubuntu/+source/linux/3.2.0-119.162 ubuntu-security-announce mailing list ubuntu-security-announce@lists.ubuntu.com Modify settings or unsubscribe at: https://lists.ubuntu.com/mailman/listinfo/ubuntu-security-announce";
}
