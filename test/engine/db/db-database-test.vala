/*
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

class Geary.Db.DatabaseTest : TestCase {


    public DatabaseTest() {
        base("Geary.Db.DatabaseTest");
        add_test("transient_open", transient_open);
        add_test("open_existing", open_existing);
        add_test("open_create_file", open_create_file);
        add_test("open_create_dir", open_create_dir);
        add_test("open_create_dir_existing", open_create_dir_existing);
        add_test("open_check_corruption", open_check_corruption);
        add_test("open_create_check", open_create_check);
    }

    public void transient_open() throws Error {
        Database db = new Geary.Db.Database.transient();
        db.open.begin(Geary.Db.DatabaseFlags.NONE, null, this.async_completion);
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();
    }

    public void open_existing() throws Error {
        GLib.FileIOStream stream;
        GLib.File tmp_file = GLib.File.new_tmp(
            "geary-db-database-test-XXXXXX", out stream
        );

        Database db = new Geary.Db.Database.persistent(tmp_file);
        db.open.begin(Geary.Db.DatabaseFlags.NONE, null, this.async_completion);
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        tmp_file.delete();
    }

    public void open_create_file() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        Database db = new Geary.Db.Database.persistent(
            tmp_dir.get_child("test.db")
        );
        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE, null, this.async_completion
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        db.file.delete();
        tmp_dir.delete();
    }

    public void open_create_dir() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        Database db = new Geary.Db.Database.persistent(
            tmp_dir.get_child("nonexistent").get_child("test.db")
        );
        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_DIRECTORY |
            Geary.Db.DatabaseFlags.CREATE_FILE,
            null,
            this.async_completion
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        db.file.delete();
        db.file.get_parent().delete();
        tmp_dir.delete();
    }

    public void open_create_dir_existing() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        Database db = new Geary.Db.Database.persistent(
            tmp_dir.get_child("test.db")
        );
        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_DIRECTORY |
            Geary.Db.DatabaseFlags.CREATE_FILE,
            null,
            this.async_completion
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        db.file.delete();
        tmp_dir.delete();
    }

    public void open_check_corruption() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        Database db = new Geary.Db.Database.persistent(
            tmp_dir.get_child("test.db")
        );
        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_FILE |
            Geary.Db.DatabaseFlags.CHECK_CORRUPTION,
            null,
            this.async_completion
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        db.file.delete();
        tmp_dir.delete();
    }

    public void open_create_check() throws Error {
        GLib.File tmp_dir = GLib.File.new_for_path(
            GLib.DirUtils.make_tmp("geary-db-database-test-XXXXXX")
        );

        Database db = new Geary.Db.Database.persistent(
            tmp_dir.get_child("nonexistent").get_child("test.db")
        );
        db.open.begin(
            Geary.Db.DatabaseFlags.CREATE_DIRECTORY |
            Geary.Db.DatabaseFlags.CREATE_FILE |
            Geary.Db.DatabaseFlags.CHECK_CORRUPTION,
            null,
            this.async_completion
        );
        db.open.end(async_result());

        // Need to get a connection since the database doesn't
        // actually get created until then
        db.get_primary_connection();

        db.file.delete();
        db.file.get_parent().delete();
        tmp_dir.delete();
    }

}
