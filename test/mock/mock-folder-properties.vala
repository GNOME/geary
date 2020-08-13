/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Mock.FolderPoperties : Geary.FolderProperties {


    public FolderPoperties() {
        base(
            0,
            0,
            Geary.Trillian.UNKNOWN,
            Geary.Trillian.UNKNOWN,
            Geary.Trillian.UNKNOWN,
            false,
            false,
            false
        );
    }

}
