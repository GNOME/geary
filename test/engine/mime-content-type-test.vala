/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Mime.ContentTypeTest : Gee.TestCase {

    public ContentTypeTest() {
        base("Geary.Mime.ContentTypeTest");
        add_test("is_default", is_default);
        add_test("get_file_name_extension", get_file_name_extension);
        add_test("guess_type_from_name", guess_type_from_name);
        add_test("guess_type_from_buf", guess_type_from_buf);
    }

    public void is_default() {
        assert(new ContentType("application", "octet-stream", null).is_default());
    }

    public void get_file_name_extension() {
        assert(new ContentType("image", "jpeg", null).get_file_name_extension() == ".jpeg");
        assert(new ContentType("test", "unknown", null).get_file_name_extension() == null);
    }

    public void guess_type_from_name() {
        try {
            assert(ContentType.guess_type("test.png", null).is_type("image", "png"));
        } catch (Error err) {
            assert_not_reached();
        }

        try {
            assert(ContentType.guess_type("foo.test", null).get_mime_type() == ContentType.DEFAULT_CONTENT_TYPE);
        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void guess_type_from_buf() {
        Memory.ByteBuffer png = new Memory.ByteBuffer(
            {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a}, 8 // PNG magic
        );
        Memory.ByteBuffer empty = new Memory.ByteBuffer({0x0}, 1);

        try {
            assert(ContentType.guess_type(null, png).is_type("image", "png"));
        } catch (Error err) {
            assert_not_reached();
        }

        try {
            assert(ContentType.guess_type(null, empty).get_mime_type() == ContentType.DEFAULT_CONTENT_TYPE);
        } catch (Error err) {
            assert_not_reached();
        }
    }

}
