/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockFolderRoot : FolderRoot {

    public MockFolderRoot(string name) {
        base(name, false, false);
    }

}
