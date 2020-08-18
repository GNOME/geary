/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class MailMerge.TestProcessor : ValaUnit.TestCase {


    private class MockEmailIdentifier : Geary.EmailIdentifier {


        private int id;


        public MockEmailIdentifier(int id) {
            this.id = id;
        }

        public override uint hash() {
            return GLib.int_hash(this.id);
        }

        public override bool equal_to(Geary.EmailIdentifier other) {
            return (
                this.get_type() == other.get_type() &&
                this.id == ((MockEmailIdentifier) other).id
            );
        }


        public override string to_string() {
            return "%s(%d)".printf(
                this.get_type().name(),
                this.id
            );
        }

        public override GLib.Variant to_variant() {
            return new GLib.Variant.int32(id);
        }

        public override int natural_sort_comparator(Geary.EmailIdentifier other) {
            MockEmailIdentifier? other_mock = other as MockEmailIdentifier;
            return (other_mock == null) ? 1 : this.id - other_mock.id;
        }

    }


    public TestProcessor() {
        base("MailMerge.TestProcessor");
        add_test("contains_field", contains_field);
        add_test("is_mail_merge_template", is_mail_merge_template);
        add_test("identity_merge", identity_merge);
        add_test("subject_merge", subject_merge);
    }

    public void contains_field() throws GLib.Error {
        assert_true(Processor.contains_field("{{test}}"), "{{test}}");
        assert_true(Processor.contains_field("test {{test}}"), "test {{test}}");
        assert_true(Processor.contains_field("test {{test}} test"), "test {{test}} test");
        assert_true(Processor.contains_field("test {{test}}"), "test {{test}}");

        assert_false(Processor.contains_field("{{test"), "{{test");
        assert_false(Processor.contains_field("{{test}"), "{{test}");
        assert_false(Processor.contains_field("{test}"), "{test}");
        assert_false(Processor.contains_field("test}}"), "test}}");
        assert_false(Processor.contains_field("test {test"), "test {test");
        assert_false(Processor.contains_field("test {"), "test {");
        assert_false(Processor.contains_field("test {{"), "test {{");
    }

    public void is_mail_merge_template() throws GLib.Error {
        assert_false(
            Processor.is_mail_merge_template(string_to_email(EMPTY_MESSAGE)),
            "empty message"
        );
        assert_true(
            Processor.is_mail_merge_template(string_to_email(TEMPLATE_SUBJECT)),
            "subject"
        );
        assert_true(
            Processor.is_mail_merge_template(string_to_email(TEMPLATE_BODY)),
            "body"
        );
    }

    public void identity_merge() throws GLib.Error {
        var original = string_to_email(TEMPLATE_SUBJECT);
        var processor = new Processor(original);
        var merged = processor.merge(Gee.Map.empty<string,string>());

        assert_equal(merged.from.to_rfc822_string(), original.from.to_rfc822_string());
        assert_equal(merged.reply_to.to_rfc822_string(), original.reply_to.to_rfc822_string());
        assert_equal(merged.sender.to_rfc822_string(), original.sender.to_rfc822_string());
        assert_equal(merged.to.to_rfc822_string(), original.to.to_rfc822_string());
        assert_equal(merged.cc.to_rfc822_string(), original.cc.to_rfc822_string());
        assert_equal(merged.bcc.to_rfc822_string(), original.bcc.to_rfc822_string());
        assert_equal(merged.subject.to_rfc822_string(), original.subject.to_rfc822_string());
        assert_equal(merged.body_text, original.get_message().get_plain_body(false, null));
    }

    public void subject_merge() throws GLib.Error {
        var original = string_to_email(TEMPLATE_SUBJECT);
        var processor = new Processor(original);
        var merged = processor.merge(
            Geary.Collection.single_map("subject", "test")
        );

        assert_equal(merged.subject.value, "test");
    }

    private Geary.Email string_to_email(string message_text)
        throws GLib.Error {
        var message = new Geary.RFC822.Message.from_buffer(
            new Geary.Memory.StringBuffer(message_text.replace("\n","\r\n"))
        );
        return new Geary.Email.from_message(
            new MockEmailIdentifier(0), message
        );
    }

    private const string EMPTY_MESSAGE = """From: Alice <alice@example.net>
Sender: Bob <bob@example.net>
To: Charlie <charlie@example.net>
CC: Dave <dave@example.net>
BCC: Eve <eve@example.net>
Reply-To: "Alice: Personal Account" <alice@example.org>
Subject: Re: Basic text/plain message
Date: Fri, 21 Nov 1997 10:01:10 -0600
Message-ID: <3456@example.net>
In-Reply-To: <1234@local.machine.example>
References: <1234@local.machine.example>
X-Mailer: Geary Test Suite 1.0

This is the first line.

This is the second line.

""";

    private const string TEMPLATE_SUBJECT = """From: Alice <alice@example.net>
Sender: Bob <bob@example.net>
To: Charlie <charlie@example.net>
CC: Dave <dave@example.net>
BCC: Eve <eve@example.net>
Reply-To: "Alice: Personal Account" <alice@example.org>
Subject: {{subject}}
Date: Fri, 21 Nov 1997 10:01:10 -0600
Message-ID: <3456@example.net>
In-Reply-To: <1234@local.machine.example>
References: <1234@local.machine.example>
X-Mailer: Geary Test Suite 1.0

This is the first line.

This is the second line.

""";

    private const string TEMPLATE_BODY = """From: Alice <alice@example.net>
Sender: Bob <bob@example.net>
To: Charlie <charlie@example.net>
CC: Dave <dave@example.net>
BCC: Eve <eve@example.net>
Reply-To: "Alice: Personal Account" <alice@example.org>
Subject: Re: Basic text/plain message
Date: Fri, 21 Nov 1997 10:01:10 -0600
Message-ID: <3456@example.net>
In-Reply-To: <1234@local.machine.example>
References: <1234@local.machine.example>
X-Mailer: Geary Test Suite 1.0

Hello {{name}}!

""";

}
