/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// All Mail generally is the same as other mail folders, but it doesn't support key features,
// like archiving (since all messages are in the archive).
//
// Service-specific accounts can use this or subclass it for further customization

private class Geary.ImapEngine.GenericAllMailFolder : GenericFolder {
    public GenericAllMailFolder(GenericAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
}

