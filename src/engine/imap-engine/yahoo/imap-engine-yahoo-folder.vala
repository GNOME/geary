/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.YahooFolder : GenericFolder {
    public YahooFolder(YahooAccount account,
                       ImapDB.Folder local_folder,
                       SpecialFolderType special_folder_type) {
        base (account, local_folder, special_folder_type);
    }
}
