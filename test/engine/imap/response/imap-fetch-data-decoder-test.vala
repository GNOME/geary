/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Imap.FetchDataDecoderTest : TestCase {


    public FetchDataDecoderTest() {
        base("Geary.Imap.FetchDataDecoderTest");
        add_test("envelope_basic", envelope_basic);
        add_test(
            "envelope_mailbox_missing_mailbox_name_quirk",
            envelope_mailbox_missing_mailbox_name_quirk
        );
        add_test(
            "envelope_mailbox_missing_host_name_quirk",
            envelope_mailbox_missing_host_name_quirk
        );
    }

    public void envelope_basic() throws GLib.Error {
        ListParameter env = new ListParameter();
        env.add(new QuotedStringParameter("Wed, 17 Jul 1996 02:23:25 -0700 (PDT)"));
        env.add(new QuotedStringParameter("Test subject"));

        // From
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));

        // Sender
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));

        // Reply-To
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));

        env.add(new ListParameter.single(new_mailbox_structure("To", "to", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("Cc", "cc", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("Bcc", "bcc", "example.com")));

        // In-Reply-To
        env.add(new QuotedStringParameter("<1234@example.com>"));

        // Message-Id
        env.add(new QuotedStringParameter("<5678@example.com>"));

        var test_article = new EnvelopeDecoder(new Quirks());
        var decoded_generic = test_article.decode(env);
        var decoded = decoded_generic as Envelope;

        assert_non_null(decoded, "decoded type");
        assert_non_null(decoded.sent, "decoded sent");
        assert_equal(decoded.subject.value, "Test subject");
        assert_equal(decoded.from.to_rfc822_string(), "From <from@example.com>");
        assert_equal(decoded.sender.to_rfc822_string(), "From <from@example.com>");
        assert_equal(decoded.reply_to.to_rfc822_string(), "From <from@example.com>");

        assert_non_null(decoded.to, "to");
        assert_equal(decoded.to.to_rfc822_string(), "To <to@example.com>");

        assert_non_null(decoded.cc, "cc");
        assert_equal(decoded.cc.to_rfc822_string(), "Cc <cc@example.com>");

        assert_non_null(decoded.bcc, "bcc");
        assert_equal(decoded.bcc.to_rfc822_string(), "Bcc <bcc@example.com>");

        assert_non_null(decoded.in_reply_to, "in_reply_to");
        assert_equal(decoded.in_reply_to.to_rfc822_string(), "<1234@example.com>");

        assert_non_null(decoded.message_id, "message_id");
        assert_equal(decoded.message_id.to_rfc822_string(), "<5678@example.com>");
    }

    public void envelope_mailbox_missing_mailbox_name_quirk() throws GLib.Error {
        ListParameter env = new ListParameter();
        env.add(new QuotedStringParameter("Wed, 17 Jul 1996 02:23:25 -0700 (PDT)"));
        env.add(new QuotedStringParameter("Test subject"));
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));

        env.add(new ListParameter.single(new_mailbox_structure("To", "BOGUS", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("Cc", "cc", "example.com")));
        env.add(NilParameter.instance);
        env.add(NilParameter.instance);
        env.add(NilParameter.instance);

        var quirks = new Quirks();
        quirks.empty_envelope_mailbox_name = "BOGUS";

        var test_article = new EnvelopeDecoder(quirks);
        var decoded = test_article.decode(env) as Envelope;

        assert_non_null(decoded.to, "to");
        assert_equal(decoded.to.to_rfc822_string(), "To <@example.com>");
        assert_non_null(decoded.cc, "cc");
        assert_equal(decoded.cc.to_rfc822_string(), "Cc <cc@example.com>");
    }

    public void envelope_mailbox_missing_host_name_quirk() throws GLib.Error {
        ListParameter env = new ListParameter();
        env.add(new QuotedStringParameter("Wed, 17 Jul 1996 02:23:25 -0700 (PDT)"));
        env.add(new QuotedStringParameter("Test subject"));
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));
        env.add(new ListParameter.single(new_mailbox_structure("From", "from", "example.com")));

        env.add(new ListParameter.single(new_mailbox_structure("To name", "to", "BOGUS")));
        env.add(new ListParameter.single(new_mailbox_structure("Cc", "cc", "example.com")));
        env.add(NilParameter.instance);
        env.add(NilParameter.instance);
        env.add(NilParameter.instance);

        var quirks = new Quirks();
        quirks.empty_envelope_host_name = "BOGUS";

        var test_article = new EnvelopeDecoder(quirks);
        var decoded = test_article.decode(env) as Envelope;

        assert_non_null(decoded.to, "to");
        assert_equal(decoded.to.to_rfc822_string(), "To name <to>");
        assert_non_null(decoded.cc, "cc");
        assert_equal(decoded.cc.to_rfc822_string(), "Cc <cc@example.com>");
    }

    private ListParameter new_mailbox_structure(string name, string local, string domain) {
        ListParameter mailbox = new ListParameter();
        mailbox.add(new QuotedStringParameter(name));
        mailbox.add(NilParameter.instance);
        mailbox.add(new QuotedStringParameter(local));
        mailbox.add(new QuotedStringParameter(domain));
        return mailbox;
    }
}
