/*
 * Copyright 2016 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.AttachmentTest : Gee.TestCase {

    private const string ATTACHMENT_ID = "test-id";
    private const string CONTENT_TYPE = "image/png";
    private const string CONTENT_ID = "test-content-id";
    private const string CONTENT_DESC = "Mea navis volitans anguillis plena est";
    private const string FILE_PATH = "../icons/hicolor/16x16/apps/geary.png";

    private Mime.ContentType? content_type;
    private Mime.ContentType? default_type;
    private Mime.ContentDisposition? content_disposition;
    private File? file;

    private class TestAttachment : Attachment {
        // A test article

        internal TestAttachment(string id,
                                Mime.ContentType content_type,
                                string? content_id,
                                string? content_description,
                                Mime.ContentDisposition content_disposition,
                                string? content_filename,
                                File file,
                                int64 filesize) {
            base(id, content_type, content_id, content_description,
                 content_disposition, content_filename, file, filesize);
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
    }

    public override void set_up() {
        try {
            this.content_type = Mime.ContentType.deserialize(CONTENT_TYPE);
            this.default_type = Mime.ContentType.deserialize(Mime.ContentType.DEFAULT_CONTENT_TYPE);
            this.content_disposition = new Mime.ContentDisposition("attachment", null);
            // XXX this will break as soon as the test runner is not
            // launched from the project root dir
            this.file = File.new_for_path("../icons/hicolor/16x16/apps/geary.png");

        } catch (Error err) {
            assert_not_reached();
        }
    }

    public void get_safe_file_name_with_content_name() {
        const string TEST_FILENAME = "test-filename.png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file,
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == TEST_FILENAME);
    }

    public void get_safe_file_name_with_bad_content_name() {
        const string TEST_FILENAME = "test-filename.jpg";
        const string RESULT_FILENAME = "test-filename.jpg.png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file,
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_bad_file_name() {
        const string TEST_FILENAME = "test-filename";
        const string RESULT_FILENAME = "test-filename.png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file,
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_no_content_name() {
        const string RESULT_FILENAME = CONTENT_ID + ".png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.content_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            null,
            this.file,
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_no_content_name_or_id() {
        const string RESULT_FILENAME = ATTACHMENT_ID + ".png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.content_type,
            null,
            CONTENT_DESC,
            content_disposition,
            null,
            this.file,
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_alt_file_name() {
        const string ALT_TEXT = "some text";
        const string RESULT_FILENAME = "some text.png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.content_type,
            null,
            CONTENT_DESC,
            content_disposition,
            null,
            this.file,
            742
        );

        test.get_safe_file_name.begin(ALT_TEXT, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

    public void get_safe_file_name_with_default_content_type() {
        const string TEST_FILENAME = "test-filename.png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.default_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            this.file,
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == TEST_FILENAME);
    }

    public void get_safe_file_name_with_default_content_type_bad_file_name() {
        const string TEST_FILENAME = "test-filename.jpg";
        const string RESULT_FILENAME = "test-filename.jpg.png";
        Attachment test = new TestAttachment(
            ATTACHMENT_ID,
            this.default_type,
            CONTENT_ID,
            CONTENT_DESC,
            content_disposition,
            TEST_FILENAME,
            // XXX this will break as soon as the test runner is not
            // launched from the project root dir
            File.new_for_path("../icons/hicolor/16x16/apps/geary.png"),
            742
        );

        test.get_safe_file_name.begin(null, (obj, ret) => {
                async_complete(ret);
            });

        assert(test.get_safe_file_name.end(async_result()) == RESULT_FILENAME);
    }

}
