/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.MailboxAddressTest : Gee.TestCase {

    public MailboxAddressTest() {
        base("Geary.RFC822.MailboxAddressTest");
        add_test("is_valid_address", is_valid_address);
        add_test("unescaped_constructor", unescaped_constructor);
        add_test("is_spoofed", is_spoofed);
        add_test("has_distinct_name", has_distinct_name);
        add_test("to_full_display", to_full_display);
        add_test("to_short_display", to_short_display);
        // latter depends on the former, so test that first
        add_test("to_rfc822_address", to_rfc822_address);
        add_test("to_rfc822_string", to_rfc822_string);
    }

    public void is_valid_address() {
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
    }

    public void unescaped_constructor() {
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

    public void is_spoofed() {
        assert(new MailboxAddress(null, "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test test", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test  test", "example@example.com").is_spoofed() == false);
        assert(new MailboxAddress("test?", "example@example.com").is_spoofed() == false);

        assert(new MailboxAddress("test@example.com", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("test @ example . com", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("\n", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("\n", "example@example.com").is_spoofed() == true);
        assert(new MailboxAddress("test", "example@\nexample@example.com").is_spoofed() == true);
        assert(new MailboxAddress("test", "example@example@example.com").is_spoofed() == true);

        try {
            assert(new MailboxAddress.from_rfc822_string("\"=?utf-8?b?dGVzdCIgPHBvdHVzQHdoaXRlaG91c2UuZ292Pg==?==?utf-8?Q?=00=0A?=\" <demo@mailsploit.com>")
                   .is_spoofed() == true);
        } catch (Error err) {
            assert_no_error(err);
        }
    }

    public void has_distinct_name() {
        assert(new MailboxAddress("example", "example@example.com").has_distinct_name() == true);

        assert(new MailboxAddress("", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress(" ", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress("example@example.com", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress(" example@example.com ", "example@example.com").has_distinct_name() == false);
        assert(new MailboxAddress(" example@example.com ", "example@example.com").has_distinct_name() == false);
    }

    public void to_full_display() {
        assert(new MailboxAddress("", "example@example.com").to_full_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example.com").to_full_display() ==
               "Test <example@example.com>");
        assert(new MailboxAddress("example@example.com", "example@example.com").to_full_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example@example.com").to_full_display() ==
               "example@example@example.com");
    }

    public void to_short_display() {
        assert(new MailboxAddress("", "example@example.com").to_short_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example.com").to_short_display() ==
               "Test");
        assert(new MailboxAddress("example@example.com", "example@example.com").to_short_display() ==
               "example@example.com");
        assert(new MailboxAddress("Test", "example@example@example.com").to_short_display() ==
               "example@example@example.com");
    }

    public void to_rfc822_address() {
        assert(new MailboxAddress(null, "example@example.com").to_rfc822_address() ==
               "example@example.com");
        //assert(new MailboxAddress(null, "test test@example.com").to_rfc822_address() ==
        //       "\"test test\"@example.com");
        //assert(new MailboxAddress(null, "test\" test@example.com").to_rfc822_address() ==
        //       "\"test\" test\"@example.com");
        //assert(new MailboxAddress(null, "test\"test@example.com").to_rfc822_address() ==
        //       "\"test\"test\"@example.com");
        assert(new MailboxAddress(null, "test@test@example.com").to_rfc822_address() ==
               "\"test@test\"@example.com");
        assert(new MailboxAddress(null, "©@example.com").to_rfc822_address() ==
               "\"=?iso-8859-1?b?qQ==?=\"@example.com");
        assert(new MailboxAddress(null, "😸@example.com").to_rfc822_address() ==
               "\"=?UTF-8?b?8J+YuA==?=\"@example.com");
    }

    public void to_rfc822_string() {
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
    }

}
