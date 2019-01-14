/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.FolderPathTest : TestCase {

    public FolderPathTest() {
        base("Geary.FolderPathTest");
        add_test("get_child_from_root", get_child_from_root);
        add_test("get_child_from_child", get_child_from_child);
        add_test("root_is_root", root_is_root);
        add_test("child_is_not_root", root_is_root);
    }

    public void get_child_from_root() throws GLib.Error {
        assert_string(
            ">test",
            new Geary.FolderRoot(false).get_child("test").to_string()
        );
    }

    public void get_child_from_child() throws GLib.Error {
        assert_string(
            ">test1>test2",
            new Geary.FolderRoot(false)
            .get_child("test1").get_child("test2").to_string()
        );
    }

    public void root_is_root() throws GLib.Error {
        assert_true(new Geary.FolderRoot(false).is_root);
    }

    public void child_root_is_not_root() throws GLib.Error {
        assert_false(new Geary.FolderRoot(false).get_child("test").is_root);
    }

}
