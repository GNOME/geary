/*
 * Copyright 2018-2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.RFC822.MailboxAddressesTest : TestCase {

    public MailboxAddressesTest() {
        base("Geary.RFC822.MailboxAddressesTest");
        add_test("from_rfc822_string_encoded", from_rfc822_string_encoded);
        add_test("from_rfc822_string_quoted", from_rfc822_string_quoted);
        add_test("to_rfc822_string", to_rfc822_string);
        add_test("contains_all", contains_all);
        add_test("merge", merge);
        add_test("equal_to", equal_to);
        add_test("hash", hash);
    }

    public void from_rfc822_string_encoded() throws GLib.Error {
        MailboxAddresses addrs = new MailboxAddresses.from_rfc822_string("test@example.com");
        assert_equal<int?>(addrs.size, 1);

        addrs = new MailboxAddresses.from_rfc822_string("test1@example.com, test2@example.com");
        assert_equal<int?>(addrs.size, 2);

        // Courtesy Mailsploit https://www.mailsploit.com
        addrs = new MailboxAddresses.from_rfc822_string("\"=?utf-8?b?dGVzdCIgPHBvdHVzQHdoaXRlaG91c2UuZ292Pg==?==?utf-8?Q?=00=0A?=\" <demo@mailsploit.com>");
        assert_equal<int?>(addrs.size, 1);

        // Courtesy Mailsploit https://www.mailsploit.com
        addrs = new MailboxAddresses.from_rfc822_string("\"=?utf-8?Q?=42=45=47=49=4E=20=2F=20=28=7C=29=7C=3C=7C=3E=7C=40=7C=2C=7C=3B=7C=3A=7C=5C=7C=22=7C=2F=7C=5B=7C=5D=7C=3F=7C=2E=7C=3D=20=2F=20=00=20=50=41=53=53=45=44=20=4E=55=4C=4C=20=42=59=54=45=20=2F=20=0D=0A=20=50=41=53=53=45=44=20=43=52=4C=46=20=2F=20?==?utf-8?b?RU5E=?=\",        <demo@mailsploit.com>");
        assert_equal<int?>(addrs.size, 2);
    }

    public void from_rfc822_string_quoted() throws GLib.Error {
        MailboxAddresses addrs = new MailboxAddresses.from_rfc822_string(
            "\"Surname, Name\" <mail@example.com>"
        ) ;
        assert_equal<int?>(addrs.size, 1);
        assert_equal(addrs[0].name, "Surname, Name");
        assert_equal(addrs[0].address, "mail@example.com");
        assert_equal(
            addrs.to_rfc822_string(), "\"Surname, Name\" <mail@example.com>"
        );
    }

    public void to_rfc822_string() throws GLib.Error {
        assert(new MailboxAddresses().to_rfc822_string() == "");
        assert(new_addreses({ "test1@example.com" })
               .to_rfc822_string() == "test1@example.com");
        assert(new_addreses({ "test1@example.com", "test2@example.com" })
               .to_rfc822_string() == "test1@example.com, test2@example.com");
    }

    public void contains_all() throws GLib.Error {
        var mailboxes_a = new_addreses({ "test1@example.com" });
        var mailboxes_b = new_addreses({ "test1@example.com" });
        var mailboxes_c = new_addreses({ "test2@example.com" });

        assert_true(mailboxes_a.contains_all(mailboxes_a));
        assert_true(mailboxes_a.contains_all(mailboxes_b));
        assert_false(mailboxes_a.contains_all(mailboxes_c));

        assert_true(
            new_addreses({ "test1@example.com", "test2@example.com" }).contains_all(
                new_addreses({ "test1@example.com", "test2@example.com" })
            )
        );
        assert_true(
            new_addreses({ "test1@example.com", "test2@example.com" }).contains_all(
                new_addreses({ "test2@example.com", "test1@example.com" })
            )
        );

        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).contains_all(
                new_addreses({ "test1@example.com" })
            )
        );
        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).contains_all(
                new_addreses({ "test1@example.com", "test3@example.com" })
            )
        );
    }

    public void merge() throws GLib.Error {
        var a1 = new MailboxAddress(null, "a@example.com");
        var b = new MailboxAddress(null, "b@example.com");
        var a2 = new MailboxAddress(null, "a@example.com");
        var list = new MailboxAddresses.single(a1);

        assert_equal<int?>(list.merge_mailbox(b).size, 2);
        assert_equal<int?>(list.merge_mailbox(a2).size, 1);

        assert_equal<int?>(list.merge_list(new MailboxAddresses.single(b)).size, 2);
        assert_equal<int?>(list.merge_list(new MailboxAddresses.single(a2)).size, 1);
    }


    public void equal_to() throws GLib.Error {
        var mailboxes_a = new_addreses({ "test1@example.com" });
        var mailboxes_b = new_addreses({ "test1@example.com" });
        var mailboxes_c = new_addreses({ "test2@example.com" });

        assert_true(mailboxes_a.equal_to(mailboxes_a));
        assert_true(mailboxes_a.equal_to(mailboxes_b));
        assert_false(mailboxes_a.equal_to(mailboxes_c));

        assert_true(
            new_addreses({ "test1@example.com", "test2@example.com" }).equal_to(
                new_addreses({ "test1@example.com", "test2@example.com" })
            )
        );
        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).equal_to(
                new_addreses({ "test2@example.com", "test1@example.com" })
            )
        );
        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).equal_to(
                new_addreses({ "test1@example.com" })
            )
        );
        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).equal_to(
                new_addreses({ "test1@example.com", "test3@example.com" })
            )
        );
    }

    public void hash() throws GLib.Error {
        var mailboxes_a = new_addreses({ "test1@example.com" });
        var mailboxes_b = new_addreses({ "test1@example.com" });
        var mailboxes_c = new_addreses({ "test2@example.com" });

        assert_true(mailboxes_a.hash() == mailboxes_a.hash());
        assert_true(mailboxes_a.hash() == mailboxes_b.hash());
        assert_false(mailboxes_a.hash() == mailboxes_c.hash());

        assert_true(
            new_addreses({ "test1@example.com", "test2@example.com" }).hash() ==
            new_addreses({ "test1@example.com", "test2@example.com" }).hash()
        );
        assert_true(
            new_addreses({ "test1@example.com", "test2@example.com" }).hash() ==
            new_addreses({ "test2@example.com", "test1@example.com" }).hash()
        );

        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).hash() ==
            new_addreses({ "test1@example.com" }).hash()
        );
        assert_false(
            new_addreses({ "test1@example.com", "test2@example.com" }).hash() ==
            new_addreses({ "test1@example.com", "test3@example.com" }).hash()
        );
    }

    private MailboxAddresses new_addreses(string[] address_strings) {
        Gee.List<MailboxAddress> addresses = new Gee.LinkedList<MailboxAddress>();
        foreach (string address in address_strings) {
            addresses.add(new MailboxAddress(null, address));
        }
        return new MailboxAddresses(addresses);
    }
}
