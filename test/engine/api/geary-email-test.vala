/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.EmailTest: TestCase {


    private const string BASIC_TEXT_PLAIN = "basic-text-plain.eml";
    private const string BASIC_MULTIPART_ALTERNATIVE =
        "basic-multipart-alternative.eml";


    public EmailTest() {
        base("Geary.EmailTest");
        add_test("email_from_basic_message", email_from_basic_message);
        add_test("email_from_multipart", email_from_multipart);
    }

    public void email_from_basic_message() throws GLib.Error {
        var message = resource_to_message(BASIC_TEXT_PLAIN);
        var email = new Email.from_message(new Mock.EmailIdentifer(0), message);

        assert_non_null(email);
        assert_non_null(email.subject);
        assert_equal(email.subject.to_string(), "Re: Basic text/plain message");
    }

    public void email_from_multipart() throws GLib.Error {
        var message = resource_to_message(BASIC_MULTIPART_ALTERNATIVE);
        var email = new Email.from_message(new Mock.EmailIdentifer(0), message);

        assert_non_null(email);
        assert_non_null(email.subject);
        assert_equal(email.subject.to_string(), "Re: Basic text/html message");
    }

    private RFC822.Message resource_to_message(string path) throws GLib.Error {
        GLib.File resource =
            GLib.File.new_for_uri(RESOURCE_URI).resolve_relative_path(path);

        uint8[] contents;
        resource.load_contents(null, out contents, null);

        return new RFC822.Message.from_buffer(
            new Geary.Memory.ByteBuffer(contents, contents.length)
        );
    }

}
