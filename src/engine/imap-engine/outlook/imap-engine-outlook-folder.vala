/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OutlookFolder : GenericFolder {
    public OutlookFolder(OutlookAccount account, Imap.Account remote,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local_folder, special_folder_type);
    }
}
