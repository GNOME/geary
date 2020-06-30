/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

// Defined by CMake build script.
extern const string _SOURCE_ROOT_DIR;

class Geary.AttachmentTest : TestCase {

    private const string CONTENT_TYPE = "image/svg+xml";
    private const string CONTENT_ID = "test-content-id";
    private const string CONTENT_DESC = "Mea navis volitans anguillis plena est";
    private const string FILE_PATH = "icons/hicolor/scalable/apps/org.gnome.Geary.svg";

    private Mime.ContentType? content_type;
    private Mime.ContentType? default_type;
    private Mime.ContentDisposition? content_disposition;
    private File? file;


    private class TestAttachment : Attachment {
        // A test article

        internal TestAttachment(Mime.ContentType content_type,
                                string? content_id,
                                string? content_description,
                                Mime.ContentDisposition content_disposition,
                                string? content_filename,
                                GLib.File file) {
            base(content_type, content_id, content_description,
                 content_disposition, content_filename);
            set_file_info(file, 742);
        }

    }

    public AttachmentTest() {
        base("Geary.AttachmentTest");
        add_test("get_safe_file_name_with_content_name",
                 get_safe_file_name_with_content_name);
        add_test("get_safe_file_name_with_bad_content_name",
                 get_safe_file_name_with_bad_content_name);
        add_test("get_safe_file_name_with_bad_file_name",
                 get_safe_file_name_with_bad_file_name);
        add_test("get_safe_file_name_with_alt_file_name",
                 get_safe_file_name_with_alt_file_name);
        add_test("get_safe_file_name_with_no_content_name",
                 get_safe_file_name_with_no_content_name);
        add_test("get_safe_file_name_with_no_content_name_or_id",
                 get_safe_file_name_with_no_content_name_or_id);
        add_test("get_safe_file_name_with_default_content_type",
                 get_safe_file_name_with_default_content_type);
        add_test("get_safe_file_name_with_default_content_type_bad_file_name",
                 get_safe_file_name_with_default_content_type_bad_file_name);
        add_test("get_safe_file_name_with_unknown_content_type",
                 get_safe_file_name_with_unknown_content_type);
    }

    public override void set_up() throws GLib.Error {
        this.content_type = Mime.ContentType.parse(CONTENT_TYPE);
        this.default_type = Mime.ContentType.ATTACHMENT_DEFAULT;
        this.content_disposition = new Mime.ContentDisposition("attachment", null);

        File source = File.new_for_path(_SOURCE_ROOT_DIR);
        this.file = source.get_child(FILE_PATH);
    }

    public void get_safe_file_name_with_content_name() throws Error {
        const string TEST_FILENAME = "test-filename.svg";
        Attachment test = new TestAttachment(
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == TEST_FILENAME);
    }

    public void get_safe_file_name_with_bad_content_name() throws Error {
        const string TEST_FILENAME = "test-filename.jpg";
        const string RESULT_FILENAME = "test-filename.jpg.svg";
        Attachment test = new TestAttachment(
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_bad_file_name() throws Error {
        const string TEST_FILENAME = "test-filename";
        const string RESULT_FILENAME = "test-filename.svg";
        Attachment test = new TestAttachment(
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_no_content_name() throws Error {
        const string RESULT_FILENAME = CONTENT_ID + ".svg";
        Attachment test = new TestAttachment(
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            null,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_no_content_name_or_id() throws Error {
        const string RESULT_FILENAME = "attachment.svg";
        Attachment test = new TestAttachment(
            this.content_type,
            null,
            CONTENT_DESC,
            content_disposition,
            null,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_alt_file_name() throws Error {
        const string ALT_TEXT = "some text";
        const string RESULT_FILENAME = "some text.svg";
        Attachment test = new TestAttachment(
            this.content_type,
            null,
            CONTENT_DESC,
            content_disposition,
            null,
            this.file
        );

        test.get_safe_file_name.begin(ALT_TEXT, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_default_content_type() throws Error {
        const string TEST_FILENAME = "test-filename.svg";
        Attachment test = new TestAttachment(
            this.default_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == TEST_FILENAME);
    }

    public void get_safe_file_name_with_default_content_type_bad_file_name()
        throws Error {
        const string TEST_FILENAME = "test-filename.jpg";
        const string RESULT_FILENAME = "test-filename.jpg.svg";
        Attachment test = new TestAttachment(
            this.default_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_unknown_content_type()
        throws Error {
        const string TEST_FILENAME = "test-filename.unlikely";
        Attachment test = new TestAttachment(
            this.default_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            File.new_for_path(TEST_FILENAME)
        );

        test.get_safe_file_name.begin(null, this.async_completion);

        assert_equal(test.get_safe_file_name.end(async_result()), TEST_FILENAME);
    }

}
