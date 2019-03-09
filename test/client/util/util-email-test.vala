/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Util.Email.Test : TestCase {

    public Test() {
        base("UtilEmailTest");
        add_test("null_originator", null_originator);
        add_test("from_originator", from_originator);
        add_test("sender_originator", sender_originator);
        add_test("reply_to_originator", reply_to_originator);
        add_test("reply_to_via_originator", reply_to_via_originator);
        add_test("plain_via_originator", plain_via_originator);
    }

    public void null_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(null, null, null)
        );

        assert_null(originator);
    }

    public void from_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                new Geary.RFC822.MailboxAddress("from", "from@example.com"),
                new Geary.RFC822.MailboxAddress("sender", "sender@example.com"),
                new Geary.RFC822.MailboxAddress("reply-to", "reply-to@example.com")
            )
        );

        assert_non_null(originator);
        assert_string("from", originator.name);
        assert_string("from@example.com", originator.address);
    }

    public void sender_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                null,
                new Geary.RFC822.MailboxAddress("sender", "sender@example.com"),
                new Geary.RFC822.MailboxAddress("reply-to", "reply-to@example.com")
            )
        );

        assert_non_null(originator);
        assert_string("sender", originator.name);
        assert_string("sender@example.com", originator.address);
    }

    public void reply_to_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                null,
                null,
                new Geary.RFC822.MailboxAddress("reply-to", "reply-to@example.com")
            )
        );

        assert_non_null(originator);
        assert_string("reply-to", originator.name);
        assert_string("reply-to@example.com", originator.address);
    }

    public void reply_to_via_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                new Geary.RFC822.MailboxAddress("test via bot", "bot@example.com"),
                null,
                new Geary.RFC822.MailboxAddress("test", "test@example.com")
            )
        );

        assert_non_null(originator);
        assert_string("test", originator.name);
        assert_string("test@example.com", originator.address);
    }

    public void plain_via_originator() throws GLib.Error {
        Geary.RFC822.MailboxAddress? originator = get_primary_originator(
            new_email(
                new Geary.RFC822.MailboxAddress("test via bot", "bot@example.com"),
                null,
                null
            )
        );

        assert_non_null(originator);
        assert_string("test", originator.name);
        assert_string("bot@example.com", originator.address);
    }

    private Geary.Email new_email(Geary.RFC822.MailboxAddress? from,
                                  Geary.RFC822.MailboxAddress? sender,
                                  Geary.RFC822.MailboxAddress? reply_to)
        throws GLib.Error {
        Geary.Email email = new Geary.Email(new Geary.MockEmailIdentifer(1));
        email.set_originators(
            from != null
            ? new Geary.RFC822.MailboxAddresses(Geary.Collection.single(from))
            : null,
            sender,
            reply_to != null
            ? new Geary.RFC822.MailboxAddresses(Geary.Collection.single(reply_to))
            : null
        );
        return email;
    }

}
