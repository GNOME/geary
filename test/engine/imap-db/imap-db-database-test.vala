/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.ImapDB.DatabaseTest : TestCase {


    public DatabaseTest() {
        base("Geary.ImapDb.DatabaseTest");
        add_test("open_new", open_new);
    }

    public void open_new() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        Database db = new Database(
            tmp_dir.get_child("test.db"),
            GLib.File.new_for_path(_SOURCE_ROOT_DIR).get_child("sql"),
            tmp_dir.get_child("attachments"),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_UPGRADE),
            new Geary.SimpleProgressMonitor(Geary.ProgressType.DB_VACUUM),
            "test@example.com"
        );

        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null,
            (obj, ret) => { async_complete(ret); }
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_master_connection();

        // Need to close it again to stop the GC process running
        db.close();

        db.file.delete();
        tmp_dir.delete();
    }


}
