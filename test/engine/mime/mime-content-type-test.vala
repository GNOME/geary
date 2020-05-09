/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Mime.ContentTypeTest : TestCase {

    public ContentTypeTest() {
        base("Geary.Mime.ContentTypeTest");
        add_test("static_defaults", static_defaults);
        add_test("parse", parse);
        add_test("get_file_name_extension", get_file_name_extension);
        add_test("guess_type_from_name", guess_type_from_name);
        add_test("guess_type_from_buf", guess_type_from_buf);
    }

    public void static_defaults() throws Error {
        assert_equal(
            ContentType.DISPLAY_DEFAULT.to_string(),
            "text/plain; charset=us-ascii"
        );
        assert_equal(
            ContentType.ATTACHMENT_DEFAULT.to_string(),
            "application/octet-stream"
        );
    }

    public void parse() throws GLib.Error {
        var test_article = ContentType.parse("text/plain");
        assert_equal(test_article.media_type, "text");
        assert_equal(test_article.media_subtype, "plain");

        try {
            ContentType.parse("");
            assert_not_reached();
        } catch (MimeError.PARSE error) {
            // All good
        }

        try {
            ContentType.parse("textplain");
            assert_not_reached();
        } catch (MimeError.PARSE error) {
            // All good
        }
    }

    public void get_file_name_extension() throws Error {
        assert(new ContentType("image", "jpeg", null).get_file_name_extension() == ".jpeg");
        assert(new ContentType("test", "unknown", null).get_file_name_extension() == null);
    }

    public void guess_type_from_name() throws Error {
        assert_true(
            ContentType.guess_type("test.png", null).is_type("image", "png"),
            "Expected image/png"
        );
        assert_true(
            ContentType.guess_type("foo.test", null)
            .is_same(ContentType.ATTACHMENT_DEFAULT),
            "Expected ContentType.ATTACHMENT_DEFAULT"
        );
    }

    public void guess_type_from_buf() throws Error {
        Memory.ByteBuffer png = new Memory.ByteBuffer(
            {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a}, 8 // PNG magic
        );
        Memory.ByteBuffer empty = new Memory.ByteBuffer({0x0}, 1);

        assert_true(
            ContentType.guess_type(null, png).is_type("image", "png"),
            "Expected image/png"
        );
        assert_true(
            ContentType.guess_type(null, empty)
            .is_same(ContentType.ATTACHMENT_DEFAULT),
            "Expected ContentType.ATTACHMENT_DEFAULT"
        );
    }

}
