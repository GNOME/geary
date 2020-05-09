/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ImapDB.AttachmentTest : TestCase {


    private const string ATTACHMENT_BODY = "This is an attachment.\r\n";


    public AttachmentTest() {
        base("Geary.ImapDB.AttachmentTest");
        add_test("new_from_minimal_mime_part", new_from_minimal_mime_part);
        add_test("new_from_complete_mime_part", new_from_complete_mime_part);
        add_test("new_from_inline_mime_part", new_from_inline_mime_part);
    }

    public void new_from_minimal_mime_part() throws Error {
        GMime.Part part = new_part(null, ATTACHMENT_BODY.data);
        part.set_header("Content-Type", "", Geary.RFC822.get_charset());

        Attachment test = new Attachment.from_part(
            1, new Geary.RFC822.Part(part)
        );
        assert_equal(
            test.content_type.to_string(),
            Geary.Mime.ContentType.ATTACHMENT_DEFAULT.to_string()
        );
        assert_null(test.content_id, "content_id");
        assert_null(test.content_description, "content_description");
        assert_equal<Geary.Mime.DispositionType?>(
            test.content_disposition.disposition_type, UNSPECIFIED
        );
        assert_false(test.has_content_filename, "has_content_filename");
        assert_null(test.content_filename, "content_filename");
    }

    public void new_from_complete_mime_part() throws Error {
        const string TYPE = "text/plain";
        const string ID = "test-id";
        const string DESC = "test description";
        const string NAME = "test.txt";

        GMime.Part part = new_part(null, ATTACHMENT_BODY.data);
        part.set_content_id(ID);
        part.set_content_description(DESC);
        part.set_content_disposition(
            GMime.ContentDisposition.parse(
                Geary.RFC822.get_parser_options(),
                "attachment; filename=%s".printf(NAME)
            )
        );

        Attachment test = new Attachment.from_part(
            1, new Geary.RFC822.Part(part)
        );

        assert_equal(test.content_type.to_string(), TYPE);
        assert_equal(test.content_id, ID);
        assert_equal(test.content_description, DESC);
        assert_equal<Geary.Mime.DispositionType?>(
            test.content_disposition.disposition_type, ATTACHMENT
        );
        assert_true(test.has_content_filename, "has_content_filename");
        assert_equal(NAME, test.content_filename, "content_filename");
    }

    public void new_from_inline_mime_part() throws Error {
        GMime.Part part = new_part(null, ATTACHMENT_BODY.data);
        part.set_content_disposition(
            GMime.ContentDisposition.parse(
                Geary.RFC822.get_parser_options(),
                "inline"
            )
        );

        Attachment test = new Attachment.from_part(
            1, new Geary.RFC822.Part(part)
        );

        assert_equal<Geary.Mime.DispositionType?>(
            test.content_disposition.disposition_type, INLINE
        );
    }

}

class Geary.ImapDB.AttachmentIoTest : TestCase {


    private const string ENCODED_BODY = "This is an attachment.\r\n";
    private const string DECODED_BODY = "This is an attachment.\n";

    private GLib.File? tmp_dir;
    private Geary.Db.Database? db;

    public AttachmentIoTest() {
        base("Geary.ImapDB.AttachmentIoTest");
        add_test("save_minimal_attachment", save_minimal_attachment);
        add_test("save_complete_attachment", save_complete_attachment);
        add_test("save_qp_attachment", save_qp_attachment);
        add_test("list_attachments", list_attachments);
        add_test("delete_attachments", delete_attachments);
    }

    public override void set_up() throws Error {
        this.tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-impadb-attachment-io-test-XXXXXX")
        );

        this.db = new Geary.Db.Database.transient();
        this.db.open.begin(
            Geary.Db.DatabaseFlags.NONE, null,
            this.async_completion
        );
        this.db.open.end(async_result());
        this.db.exec("""
CREATE TABLE MessageTable (
    id INTEGER PRIMARY KEY
);
""");
        this.db.exec("INSERT INTO MessageTable VALUES (1);");

        this.db.exec("""
CREATE TABLE MessageAttachmentTable (
    id INTEGER PRIMARY KEY,
    message_id INTEGER REFERENCES MessageTable ON DELETE CASCADE,
    filename TEXT,
    mime_type TEXT,
    filesize INTEGER,
    disposition INTEGER,
    content_id TEXT DEFAULT NULL,
    description TEXT DEFAULT NULL
);
""");

    }

    public override void tear_down() throws Error {
        this.db.close();
        this.db = null;

        Files.recursive_delete_async.begin(
            this.tmp_dir, GLib.Priority.DEFAULT, null,
            this.async_completion
        );
        Files.recursive_delete_async.end(async_result());
        this.tmp_dir = null;
    }

    public void save_minimal_attachment() throws Error {
        GMime.Part part = new_part(null, ENCODED_BODY.data);

        Gee.List<Attachment> attachments = Attachment.save_attachments(
            this.db.get_primary_connection(),
            this.tmp_dir,
            1,
            new Gee.ArrayList<Geary.RFC822.Part>.wrap({
                    new Geary.RFC822.Part(part)
                }),
            null
        );

        assert_equal<int?>(attachments.size, 1, "No attachment provided");

        Geary.Attachment attachment = attachments[0];
        assert_non_null(attachment.file, "Attachment file");
        assert_equal<int64?>(
            attachment.filesize,
            DECODED_BODY.data.length,
            "Attachment file size"
        );

        uint8[] buf = new uint8[4096];
        size_t len = 0;
        attachments[0].file.read().read_all(buf, out len);
        assert_equal((string) buf[0:len], DECODED_BODY);

        Geary.Db.Result result = this.db.query(
            "SELECT * FROM MessageAttachmentTable;"
        );
        assert_false(result.finished, "Row not inserted");
        assert_equal<int64?>(result.int_for("message_id"), 1, "Row message id");
        assert_equal<int64?>(
            result.int_for("filesize"),
            DECODED_BODY.data.length,
            "Row file size"
        );
        assert_false(result.next(), "Multiple rows inserted");
    }

    public void save_complete_attachment() throws Error {
        const string TYPE = "text/plain";
        const string ID = "test-id";
        const string DESCRIPTION = "test description";
        const Geary.Mime.DispositionType DISPOSITION_TYPE = INLINE;
        const string FILENAME = "test.txt";

        GMime.Part part = new_part(TYPE, ENCODED_BODY.data);
        part.set_content_id(ID);
        part.set_content_description(DESCRIPTION);
        part.set_content_disposition(
            GMime.ContentDisposition.parse(
                Geary.RFC822.get_parser_options(),
                "inline; filename=%s;".printf(FILENAME)
            ));

        Gee.List<Attachment> attachments = Attachment.save_attachments(
            this.db.get_primary_connection(),
            this.tmp_dir,
            1,
            new Gee.ArrayList<Geary.RFC822.Part>.wrap({
                    new Geary.RFC822.Part(part)
                }),
            null
        );

        assert_equal<int?>(attachments.size, 1, "No attachment provided");

        Geary.Attachment attachment = attachments[0];
        assert_equal(attachment.content_type.to_string(), TYPE);
        assert_equal(attachment.content_id, ID);
        assert_equal(attachment.content_description, DESCRIPTION);
        assert_equal(attachment.content_filename, FILENAME);
        assert_equal<Geary.Mime.DispositionType?>(
            attachment.content_disposition.disposition_type,
            DISPOSITION_TYPE,
            "Attachment disposition type"
        );

        uint8[] buf = new uint8[4096];
        size_t len = 0;
        attachment.file.read().read_all(buf, out len);
        assert_equal((string) buf[0:len], DECODED_BODY);

        Geary.Db.Result result = this.db.query(
            "SELECT * FROM MessageAttachmentTable;"
        );
        assert_false(result.finished, "Row not inserted");
        assert_equal<int64?>(result.int_for("message_id"), 1, "Row message id");
        assert_equal(result.string_for("mime_type"), TYPE);
        assert_equal(result.string_for("content_id"), ID);
        assert_equal(result.string_for("description"), DESCRIPTION);
        assert_equal<Geary.Mime.DispositionType?>(
            (Geary.Mime.DispositionType) result.int_for("disposition"),
            DISPOSITION_TYPE,
            "Row disposition type"
        );
        assert_equal(result.string_for("filename"), FILENAME);
        assert_false(result.next(), "Multiple rows inserted");
    }

    public void save_qp_attachment() throws Error {
        // Example courtesy https://en.wikipedia.org/wiki/Quoted-printable
        const string QP_ENCODED =
"""J'interdis aux marchands de vanter trop leur marchandises. Car ils se font =
vite p=C3=A9dagogues et t'enseignent comme but ce qui n'est par essence qu'=
un moyen, et te trompant ainsi sur la route =C3=A0 suivre les voil=C3=A0 bi=
ent=C3=B4t qui te d=C3=A9gradent, car si leur musique est vulgaire ils te f=
abriquent pour te la vendre une =C3=A2me vulgaire.""";
        const string QP_DECODED =
"""J'interdis aux marchands de vanter trop leur marchandises. Car ils se font vite pédagogues et t'enseignent comme but ce qui n'est par essence qu'un moyen, et te trompant ainsi sur la route à suivre les voilà bientôt qui te dégradent, car si leur musique est vulgaire ils te fabriquent pour te la vendre une âme vulgaire.""";
        GMime.Part part = new_part(
            "text/plain; charset=utf-8",
            QP_ENCODED.data,
            GMime.ContentEncoding.QUOTEDPRINTABLE
        );

        Gee.List<Attachment> attachments = Attachment.save_attachments(
            this.db.get_primary_connection(),
            this.tmp_dir,
            1,
            new Gee.ArrayList<Geary.RFC822.Part>.wrap({
                    new Geary.RFC822.Part(part)
                }),
            null
        );

        assert_equal<int?>(attachments.size, 1, "No attachment provided");

        uint8[] buf = new uint8[4096];
        size_t len = 0;
        attachments[0].file.read().read_all(buf, out len);
        assert_equal((string) buf[0:len], QP_DECODED);
    }

    public void list_attachments() throws Error {
        this.db.exec("""
INSERT INTO MessageAttachmentTable ( message_id, mime_type )
VALUES (1, 'text/plain');
""");
        this.db.exec("""
INSERT INTO MessageAttachmentTable ( message_id, mime_type )
VALUES (2, 'text/plain');
""");

        Gee.List<Attachment> loaded = Attachment.list_attachments(
            this.db.get_primary_connection(),
            GLib.File.new_for_path("/tmp"),
            1,
            null
        );

        assert_equal<int?>(loaded.size, 1, "Expected one row loaded");
        assert_equal<int64?>(loaded[0].message_id, 1, "Unexpected message id");
    }

    public void delete_attachments() throws Error {
        GMime.Part part = new_part(null, ENCODED_BODY.data);

        Gee.List<Attachment> attachments = Attachment.save_attachments(
            this.db.get_primary_connection(),
            this.tmp_dir,
            1,
            new Gee.ArrayList<Geary.RFC822.Part>.wrap({
                    new Geary.RFC822.Part(part)
                }),
            null
        );

        assert_true(attachments[0].file.query_exists(null),
                     "Attachment not saved to disk");

        this.db.exec("""
INSERT INTO MessageAttachmentTable ( message_id, mime_type )
VALUES (2, 'text/plain');
""");

        Attachment.delete_attachments(
            this.db.get_primary_connection(), this.tmp_dir, 1, null
        );

        Geary.Db.Result result = this.db.query(
            "SELECT * FROM MessageAttachmentTable;"
        );
        assert_false(result.finished);
        assert_equal<int64?>(
            result.int_for("message_id"), 2, "Unexpected message_id"
        );
        assert_false(result.next(), "Attachment not deleted from db");

        assert_false(attachments[0].file.query_exists(null),
                     "Attachment not deleted from disk");
    }

}

private GMime.Part new_part(string? mime_type,
                            uint8[] body,
                            GMime.ContentEncoding encoding = GMime.ContentEncoding.DEFAULT) {
    GMime.Part part = new GMime.Part.with_type("text", "plain");
    if (mime_type != null) {
        part.set_content_type(GMime.ContentType.parse(
            Geary.RFC822.get_parser_options(),
            mime_type
        ));
    }
    GMime.DataWrapper body_wrapper = new GMime.DataWrapper.with_stream(
        new GMime.StreamMem.with_buffer(body),
        encoding
    );
    part.set_content(body_wrapper);
    return part;
}
