/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.ImapDB.AttachmentTest : TestCase {


    private Geary.Db.Database? db;

    public AttachmentTest() {
        base("Geary.ImapDB.FolderTest");
        add_test("save_minimal_attachment", save_minimal_attachment);
    }

    public override void set_up() throws Error {
        this.db = new Geary.Db.Database.transient();
        this.db.open.begin(
            Geary.Db.DatabaseFlags.NONE, null, null,
            (obj, res) => { async_complete(res); }
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
    }

    public void save_minimal_attachment() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-impadb-foldertest-XXXXXX")
        );

        GMime.DataWrapper body = new GMime.DataWrapper.with_stream(
            new GMime.StreamMem.with_buffer(TEXT_ATTACHMENT.data),
            GMime.ContentEncoding.DEFAULT
        );
        GMime.Part attachment = new GMime.Part.with_type("text", "plain");
        attachment.set_content_object(body);
        attachment.encode(GMime.EncodingConstraint.7BIT);

        Gee.List<GMime.Part> attachments = new Gee.LinkedList<GMime.Part>();
        attachments.add(attachment);

        Geary.ImapDB.Attachment.do_save_attachments(
            this.db.get_master_connection(),
            tmp_dir,
            1,
            attachments,
            null
        );

        Geary.Db.Result result = this.db.query(
            "SELECT * FROM MessageAttachmentTable;"
        );
        assert_false(result.finished, "Row not inserted");
        assert_int(1, result.int_for("message_id"), "Message id");
        assert_false(result.next(), "Multiple rows inserted");

        Geary.Files.recursive_delete_async.begin(tmp_dir);
    }


    private const string TEXT_ATTACHMENT = "This is an attachment.\n";

}
