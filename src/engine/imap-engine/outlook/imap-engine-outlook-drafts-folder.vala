/* Copyright 2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Since Outlook doesn't support UIDPLUS, we can't delete old drafts before
 * saving a new one.  Instead of allowing their drafts folder to fill up with
 * countless revisions of every message, we simply don't expose the
 * Geary.FolderSupport.Create interface from the drafts folder, so nothing gets
 * saved at all.
 */
private class Geary.ImapEngine.OutlookDraftsFolder : MinimalFolder {
    public OutlookDraftsFolder(OutlookAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
}
