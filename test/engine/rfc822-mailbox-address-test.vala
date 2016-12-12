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
    }

    public void is_valid_address() {
        assert(Geary.RFC822.MailboxAddress.is_valid_address("john@dep.aol.museum") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test@example.com") == true);
        // This is Bug 714299
        //assert(Geary.RFC822.MailboxAddress.is_valid_address("test@example") == true);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("some context test@example.com text") == true);

        assert(Geary.RFC822.MailboxAddress.is_valid_address("john@aol...com") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("@example.com") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("@example") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("test@") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("@") == false);
        assert(Geary.RFC822.MailboxAddress.is_valid_address("") == false);
    }

}
