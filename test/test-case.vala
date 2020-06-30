/*
 * Copyright 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/** Base class for Geary unit tests. */
public class TestCase : ValaUnit.TestCase {

    /** GLib.File URI for resources in test/data. */
    public const string RESOURCE_URI = "resource:///org/gnome/GearyTest";


    public TestCase(string name) {
        base(name);
    }

    public void delete_file(File parent) throws GLib.Error {
        FileInfo info = parent.query_info(
            "standard::*",
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS
        );

        if (info.get_file_type () == FileType.DIRECTORY) {
            FileEnumerator enumerator = parent.enumerate_children(
                "standard::*",
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS
            );

            info = null;
            while (((info = enumerator.next_file()) != null)) {
                delete_file(parent.get_child(info.get_name()));
            }
        }

        parent.delete();
    }

}