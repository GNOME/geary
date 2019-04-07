/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockFolderPoperties : FolderProperties {


    public MockFolderPoperties() {
        base(
            0,
            0,
            Trillian.UNKNOWN,
            Trillian.UNKNOWN,
            Trillian.UNKNOWN,
            false,
            false,
            false
        );
    }

}
