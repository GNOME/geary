/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */


class Geary.Db.VersionedDatabaseTest : TestCase {


    public VersionedDatabaseTest() {
        base("Geary.Db.VersionedDatabaseTest");
        add_test("open_new", open_new);
    }

    public void open_new() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        GLib.File sql1 = tmp_dir.get_child("version-001.sql");
        sql1.create(
            GLib.FileCreateFlags.NONE
        ).write("CREATE TABLE TestTable (id INTEGER PRIMARY KEY, col TEXT);".data);

        GLib.File sql2 = tmp_dir.get_child("version-002.sql");
        sql2.create(
            GLib.FileCreateFlags.NONE
        ).write("INSERT INTO TestTable (col) VALUES ('value');".data);

        VersionedDatabase db = new VersionedDatabase.persistent(
            tmp_dir.get_child("test.db"), tmp_dir
        );

        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null, this.async_completion
        );
        db.open.end(async_result());

        Geary.Db.Result result = db.query("SELECT * FROM TestTable;");
        assert_false(result.finished, "Row not inserted");
        assert_equal(result.string_for("col"), "value");
        assert_false(result.next(), "Multiple rows inserted");

        db.file.delete();
        sql1.delete();
        sql2.delete();
        tmp_dir.delete();
    }


}
