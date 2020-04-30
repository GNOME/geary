/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OtherFolder : GenericFolder {

    public OtherFolder(OtherAccount account,
                       ImapDB.Folder local_folder,
                       Folder.SpecialUse use) {
        base(account, local_folder, use);
    }

}
