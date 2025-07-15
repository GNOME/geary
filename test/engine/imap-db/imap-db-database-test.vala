/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ImapDB.DatabaseTest : TestCase {


    private GLib.File? tmp_dir = null;


    public DatabaseTest() {
        base("Geary.ImapDb.DatabaseTest");
        add_test("open_new", open_new);
        add_test("upgrade_0_6", upgrade_0_6);
        add_test("utf8_case_insensitive_collation",
                 utf8_case_insensitive_collation);
    }

    public override void set_up() throws GLib.Error {
        this.tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-imap-db-database-test-XXXXXX")
        );
    }

    public override void tear_down() throws GLib.Error {
        delete_file(this.tmp_dir);
        this.tmp_dir = null;
    }

    public void open_new() throws Error {
        Database db = new Database(
            this.tmp_dir.get_child("test.db"),
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql"),
            this.tmp_dir.get_child("attachments"),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_UPGRADE),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_VACUUM)
        );

        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null,
            this.async_completion
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        // Need to close it again to stop the GC process running
        db.close();
    }

    public void upgrade_0_6() throws Error {
        // Since the upgrade process also messes around with
        // attachments on disk which we want to be able to test, we
        // need to have a complete-ish database and attachments
        // directory hierarchy. For convenience, these are included as
        // a single compressed archive, but that means we need to
        // un-compress and unpack the archive as part of the test
        // fixture.
        const string DB_0_6_RESOURCE = "geary-0.6-db.tar.xz";
        const string DB_0_6_DIR = "geary-0.6-db";
        const string ATTACHMENT_12 = "capitalism.jpeg";

        GLib.File db_archive = GLib.File
            .new_for_uri(RESOURCE_URI)
            .resolve_relative_path(DB_0_6_RESOURCE);
        GLib.File db_dir = this.tmp_dir.get_child(DB_0_6_DIR);
        GLib.File db_file = db_dir.get_child("geary.db");
        GLib.File attachments_dir = db_dir.get_child("attachments");

        unpack_archive(db_archive, this.tmp_dir);

        // This number is the id of the last known message in the
        // database
        GLib.File message_dir = attachments_dir.get_child("43");

        // Ensure one of the expected attachments exists up
        // front. Since there are 12 known attachments, 12 should be
        // the last one in the table and exist on the file system,
        // while 13 should not.
        assert_true(
            message_dir.get_child("12").get_child(ATTACHMENT_12).query_exists(),
            "Expected attachment file"
        );
        assert_false(
            message_dir.get_child("13").query_exists(),
            "Unexpected attachment file"
        );

        Database db = new Database(
            db_file,
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql"),
            attachments_dir,
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_UPGRADE),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_VACUUM)
        );

        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null,
            this.async_completion
        );
        db.open.end(async_result());

        assert_equal<int?>(db.get_schema_version(), 30, "Post-upgrade version");

        // Since schema v22 deletes the re-creates all attachments,
        // attachment 12 should no longer exist on the file system and
        // there should be an attachment with id 24.
        assert_false(
            message_dir.get_child("12").get_child(ATTACHMENT_12).query_exists(),
            "Old attachment file not deleted"
        );
        assert_true(
            message_dir.get_child("24").get_child(ATTACHMENT_12).query_exists(),
            "New attachment dir/file not created"
        );


        // Need to close it again to stop the GC process running
        db.close();
    }

    public void utf8_case_insensitive_collation() throws GLib.Error {
        Database db = new Database(
            this.tmp_dir.get_child("test.db"),
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql"),
            this.tmp_dir.get_child("attachments"),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_UPGRADE),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_VACUUM)
        );

        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null,
            this.async_completion
        );
        db.open.end(async_result());

        db.exec("""
            CREATE TABLE Test (id INTEGER PRIMARY KEY, test_str TEXT);
            INSERT INTO Test (test_str) VALUES ('a');
            INSERT INTO Test (test_str) VALUES ('B');
            INSERT INTO Test (test_str) VALUES ('BB');
            INSERT INTO Test (test_str) VALUES ('🤯');
        """);

        string[] expected = { "🤯", "a", "BB", "B" };
        Db.Result result = db.query(
            "SELECT test_str FROM Test ORDER BY test_str COLLATE UTF8COLL DESC"
        );

        int i = 0;
        while (!result.finished) {
            assert_true(i < expected.length, "Too many rows");
            assert_equal(result.string_at(0), expected[i]);
            i++;
            result.next();
        }
        assert_true(i == expected.length, "Not enough rows");

        // Need to close it again to stop the GC process running
        db.close();
    }

    private void unpack_archive(GLib.File archive, GLib.File dest)
        throws Error {
        // GLib doesn't seem to have native support for unpacking
        // multi-file archives however, so use this fun kludge
        // instead.

        GLib.InputStream bytes = archive.read();

        GLib.Subprocess untar = new GLib.Subprocess(
            GLib.SubprocessFlags.STDIN_PIPE,
            "tar", "-xJf", "-", "-C", dest.get_path()
        );
        GLib.OutputStream stdin = untar.get_stdin_pipe();

        uint8[] buf = new uint8[4096];
        ssize_t len = 0;
        do {
            len = bytes.read(buf);
            stdin.write(buf[0:len]);
        } while (len > 0);

        stdin.close();

        untar.wait();
    }

}
