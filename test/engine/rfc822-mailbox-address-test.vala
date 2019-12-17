/*
 * Copyright 2016-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.MailboxAddressTest : TestCase {

    public MailboxAddressTest() {
        base("Geary.RFC822.MailboxAddressTest");
        add_test("is_valid_address", is_valid_address);
        add_test("unescaped_constructor", unescaped_constructor);
        add_test("from_rfc822_string_encoded", from_rfc822_string_encoded);
        add_test("prepare_header_text_part", prepare_header_text_part);
        // latter depends on the former, so test that first
        add_test("has_distinct_name", has_distinct_name);
        add_test("is_spoofed", is_spoofed);
        add_test("to_full_display", to_full_display);
        add_test("to_short_display", to_short_display);
        // latter depends on the former, so test that first
        add_test("to_rfc822_address", to_rfc822_address);
        add_test("to_rfc822_string", to_rfc822_string);
        add_test("equal_to", equal_to);
    }

    public void is_valid_address() throws Error {
        assert(Geary.RFC822.MailboxAddress.is_valid_address("john@dep.aol.museum") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test@example.com") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test.other@example.com") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test@localhost") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test2@localhost") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("some context test@example.com text") == true);

        assert(Geary.RFC822.MailboxAddress.is_valid_address("test@example") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("john@aol...com") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("@example.com") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("@example") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test@") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("@") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("") == false);

        assert(Geary.RFC822.MailboxAddress.is_valid_address("\"Surname, Name\" <mail@example.com>") == true);
    }

    public void unescaped_constructor() throws Error {
        MailboxAddress addr1 = new MailboxAddress("test1", "test2@example.com");
        assert(addr1.name == "test1");
        assert(addr1.address == "test2@example.com");
        assert(addr1.mailbox == "test2");
        assert(addr1.domain == "example.com");

        MailboxAddress addr2 = new MailboxAddress(null, "test1@test2@example.com");
        assert(addr2.address == "test1@test2@example.com");
        assert(addr2.mailbox == "test1@test2");
        assert(addr2.domain == "example.com");

        MailboxAddress addr3 = new MailboxAddress(null, "©@example.com");
        assert(addr3.address == "©@example.com");
        assert(addr3.mailbox == "©");
        assert(addr3.domain == "example.com");

        MailboxAddress addr4 = new MailboxAddress(null, "😸@example.com");
        assert(addr4.address == "😸@example.com");
        assert(addr4.mailbox == "😸");
        assert(addr4.domain == "example.com");

        MailboxAddress addr5 = new MailboxAddress(null, "example.com");
        assert(addr5.address == "example.com");
        assert(addr5.mailbox == "");
        assert(addr5.domain == "");
    }

    public void from_rfc822_string_encoded() throws Error {
        try {
            MailboxAddress addr = new MailboxAddress.from_rfc822_string("test@example.com");
            assert(addr.name == null);
            assert(addr.mailbox == "test");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("\"test\"@example.com");
            assert(addr.name == null);
            assert(addr.address == "test@example.com");
            assert(addr.mailbox == "test");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("=?UTF-8?b?dGVzdA==?=@example.com");
            assert(addr.name == null);
            assert(addr.address == "test@example.com");
            assert(addr.mailbox == "test");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("\"=?UTF-8?b?dGVzdA==?=\"@example.com");
            assert(addr.name == null);
            assert(addr.address == "test@example.com");
            assert(addr.mailbox == "test");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("<test@example.com>");
            assert(addr.name == null);
            assert(addr.address == "test@example.com");
            assert(addr.mailbox == "test");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("<\"test\"@example.com>");
            assert(addr.name == null);
            assert(addr.address == "test@example.com");
            assert(addr.mailbox == "test");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("Test 1 <test2@example.com>");
            assert(addr.name == "Test 1");
            assert(addr.address == "test2@example.com");
            assert(addr.mailbox == "test2");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("\"Test 1\" <test2@example.com>");
            assert(addr.name == "Test 1");
            assert(addr.address == "test2@example.com");
            assert(addr.mailbox == "test2");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("Test 1 <\"test2\"@example.com>");
            assert(addr.name == "Test 1");
            assert(addr.address == "test2@example.com");
            assert(addr.mailbox == "test2");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("=?UTF-8?b?VGVzdCAx?= <test2@example.com>");
            assert(addr.name == "Test 1");
            assert(addr.address == "test2@example.com");
            assert(addr.mailbox == "test2");
            assert(addr.domain == "example.com");

            addr = new MailboxAddress.from_rfc822_string("\"=?UTF-8?b?VGVzdCAx?=\" <test2@example.com>");
            assert(addr.name == "Test 1");
            assert(addr.address == "test2@example.com");
            assert(addr.mailbox == "test2");
            assert(addr.domain == "example.com");

            // Courtesy Mailsploit https://www.mailsploit.com
            addr = new MailboxAddress.from_rfc822_string("\"=?utf-8?b?dGVzdCIgPHBvdHVzQHdoaXRlaG91c2UuZ292Pg==?==?utf-8?Q?=00=0A?=\" <demo@mailsploit.com>");
            assert(addr.name == "test <potus@whitehouse.gov>?");
            assert(addr.address == "demo@mailsploit.com");

            // Courtesy Mailsploit https://www.mailsploit.com
            addr = new MailboxAddress.from_rfc822_string("\"=?utf-8?Q?=42=45=47=49=4E=20=2F=20=28=7C=29=7C=3C=7C=3E=7C=40=7C=2C=7C=3B=7C=3A=7C=5C=7C=22=7C=2F=7C=5B=7C=5D=7C=3F=7C=2E=7C=3D=20=2F=20=00=20=50=41=53=53=45=44=20=4E=55=4C=4C=20=42=59=54=45=20=2F=20=0D=0A=20=50=41=53=53=45=44=20=43=52=4C=46=20=2F=20?==?utf-8?b?RU5E=?=\"");
            assert(addr.name == null);
            assert(addr.address == "BEGIN / (|)|<|>|@|,|;|:|\\|\"|/|[|]|?|.|= / ? PASSED NULL BYTE / \r\n PASSED CRLF / END");
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void prepare_header_text_part() throws Error {
        try {
            // Test if prepare_header_text_part() can handle crappy input without grilling the CPU
            addr = new MailboxAddress.imap(
                "=?UTF-8?Q?=22Firstname_=22=C2=AF\\=5F=28=E3=83=84=29=5F/=C2=AF=22_Lastname_via?==?UTF-8?Q?_Vendor=22_<system@vendor.com>?=",
                null,
                "=?UTF-8?Q?=22Firstname_=22=C2=AF\\=5F=28=E3=83=84=29=5F/=C2=AF=22_Lastname_via?==?UTF-8?Q?_Vendor=22_<system@vendor.com>?=",
                "vendor.com");
            assert(addr.name == "\"Firstname \"¯_(ツ)_/¯\" Lastname via Vendor\" <system@vendor.com>");
            assert(addr.mailbox == "\"Firstname \"¯_(ツ)_/¯\" Lastname via Vendor\" <system@vendor.com>");

            // A second test with the input that have been passed to prepare_header_text_part() by the pre-GMime3 tests
            MailboxAddress addr = new MailboxAddress.imap(
                "\"Firstname \"¯_(ツ)_/¯\" Lastname via=?UTF-8?Q?_Vendor=22_",
                null,
                "system",
                "vendor.com");
            assert(addr.name == "Firstname ¯_(ツ)_/¯ Lastname via=?UTF-8?Q?_Vendor=22_");
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void has_distinct_name() throws Error {
        assert(new MailboxAddress("example", "example@example.com").has_distinct_name() == true);

        assert(new MailboxAddress("", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress(" ", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress("example@example.com", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress(" example@example.com ", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress(" example@example.com ", "example@example.com").has_distinct_name() == false);

        assert(new MailboxAddress("'example@example.com'", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress("'prefix-example@example.com'", "example@example.com").has_distinct_name() == true);
    }

    public void is_spoofed() throws Error {
        assert(new MailboxAddress(null, "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test test", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test  test", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test?", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test@example.com", "test@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test@EXAMPLE.com", "test@example.com").is_spoofed() == false);
        assert(new MailboxAddress("'example@example.com'", "example@example.com").is_spoofed() == false);

        assert(new MailboxAddress("test@example.com", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("test @ example . com", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("\n", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("\n", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("test", "example@\nexample@example.com").is_spoofed() == true);
        assert(new MailboxAddress("test", "example@example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("'prefix-example@example.com'", "example@example.com").is_spoofed() == true);

        try {
            assert(new MailboxAddress.from_rfc822_string("\"=?utf-8?b?dGVzdCIgPHBvdHVzQHdoaXRlaG91c2UuZ292Pg==?==?utf-8?Q?=00=0A?=\" <demo@mailsploit.com>")
                   .is_spoofed() == true);
        } catch (Error err) {
            assert_no_error(err);
        }
    }

    public void to_full_display() throws Error {
        assert(new MailboxAddress("", "example@example.com").to_full_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example.com").to_full_display() ==
               "Test <example@example.com>");
        assert(new MailboxAddress("example@example.com", "example@example.com").to_full_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example@example.com").to_full_display() ==
               "example@example@example.com");

        assert_string(
            "\"Testerson, Test\" <test@example.com>",
            new MailboxAddress("Testerson, Test", "test@example.com").to_full_display()
        );
    }

    public void to_short_display() throws Error {
        assert(new MailboxAddress("", "example@example.com").to_short_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example.com").to_short_display() ==
               "Test");
        assert(new MailboxAddress("example@example.com", "example@example.com").to_short_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example@example.com").to_short_display() ==
               "example@example@example.com");
    }

    public void to_rfc822_address() throws GLib.Error {
        assert_string(
            "example@example.com",
            new MailboxAddress(null, "example@example.com").to_rfc822_address()
        );
        assert_string(
            "test.account@example.com",
            new MailboxAddress(null, "test.account@example.com").to_rfc822_address()
        );
        //assert(new MailboxAddress(null, "test test@example.com").to_rfc822_address() ==
        //       "\"test test\"@example.com");
        //assert(new MailboxAddress(null, "test\" test@example.com").to_rfc822_address() ==
        //       "\"test\" test\"@example.com");
        //assert(new MailboxAddress(null, "test\"test@example.com").to_rfc822_address() ==
        //       "\"test\"test\"@example.com");

        assert_string(
            "$test@example.com",
            new MailboxAddress(null, "$test@example.com").to_rfc822_address()
        );
        assert_string(
            "\"test@test\"@example.com",
            new MailboxAddress(null, "test@test@example.com").to_rfc822_address()
        );

        // RFC 2047 reserved words in the local-part must be used
        // as-is, and in particular not encoded per that RFC. See RFC
        // 2047 §5 and GNOME/geary#336
        string RFC_2074 = "libc-alpha-sc.1553427554.ndgdflaalknmibgfkpak-hi-angel=yandex.ru@sourceware.org";
        assert_string(
            RFC_2074,
            new MailboxAddress(null, RFC_2074).to_rfc822_address()
        );

        // Likewise, Unicode chars should be passed through. Note that
        // these can only be sent if a UTF8 connection is negotiated
        // with the SMTP server
        assert_string(
            "©@example.com",
            new MailboxAddress(null, "©@example.com").to_rfc822_address()
        );
        assert_string(
            "😸@example.com",
            new MailboxAddress(null, "😸@example.com").to_rfc822_address()
        );

    }

    public void to_rfc822_string() throws Error {
        assert(new MailboxAddress("", "example@example.com").to_rfc822_string() ==
               "example@example.com");
        assert(new MailboxAddress(" ", "example@example.com").to_rfc822_string() ==
               "example@example.com");
        assert(new MailboxAddress("test", "example@example.com").to_rfc822_string() ==
               "test <example@example.com>");
        assert(new MailboxAddress("test test", "example@example.com").to_rfc822_string() ==
               "test test <example@example.com>");
        assert(new MailboxAddress("example@example.com", "example@example.com").to_rfc822_string() ==
               "example@example.com");
        assert(new MailboxAddress("test?", "example@example.com").to_rfc822_string() ==
               "test? <example@example.com>");
        assert(new MailboxAddress("test@test", "example@example.com").to_rfc822_string() ==
               "\"test@test\" <example@example.com>");
        assert(new MailboxAddress(";", "example@example.com").to_rfc822_string() ==
               "\";\" <example@example.com>");
        assert(new MailboxAddress("©", "example@example.com").to_rfc822_string() ==
               "=?iso-8859-1?b?qQ==?= <example@example.com>");
        assert(new MailboxAddress("😸", "example@example.com").to_rfc822_string() ==
               "=?UTF-8?b?8J+YuA==?= <example@example.com>");

        assert_string(
            "\"Surname, Name\" <example@example.com>",
            new MailboxAddress("Surname, Name", "example@example.com").to_rfc822_string()
        );
        assert_string(
            "\"Surname, Name\" <example@example.com>",
            new MailboxAddress
            .from_rfc822_string("\"Surname, Name\" <example@example.com>")
            .to_rfc822_string()
        );
    }

    public void equal_to() throws GLib.Error {
        MailboxAddress test = new MailboxAddress("test", "example@example.com");

        assert_true(
            test.equal_to(test),
            "Object identity equality"
        );
        assert_true(
            test.equal_to(new MailboxAddress("test", "example@example.com")),
            "Mailbox identity equality"
        );
        assert_true(
            test.equal_to(new MailboxAddress(null, "example@example.com")),
            "Address equality"
        );
        assert_false(
            test.equal_to(new MailboxAddress(null, "blarg@example.com")),
            "Address inequality"
        );
    }
}
