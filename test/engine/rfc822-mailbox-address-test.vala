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
        add_test("is_spoofed", is_spoofed);
        add_test("has_distinct_name", has_distinct_name);
        add_test("to_full_display", to_full_display);
        add_test("to_short_display", to_short_display);
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
        // Technically, per
        // https://tools.ietf.org/html/rfc5322#appendix-A.1.2 this
        // would be fine as just "test? <example@example.com>",
        // i.e. without the name being quoted, but I guess GMime is
        // just being conservative here?
        assert(new MailboxAddress("test?", "example@example.com").to_rfc822_string() ==
               "\"test?\" <example@example.com>");
        assert(new MailboxAddress(";", "example@example.com").to_rfc822_string() ==
               "\";\" <example@example.com>");
    }
}
