/* Copyright 2012-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.OtherFolder : GenericFolder, FolderSupport.Archive {
    public OtherFolder(OtherAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }

    public async Geary.Revokable? archive_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        Geary.Folder? archive_folder = null;
        try {
            archive_folder = yield account.get_required_special_folder_async(Geary.SpecialFolderType.ARCHIVE, cancellable);
        } catch (Error e) {
            debug("Error looking up archive folder in %s: %s", account.to_string(), e.message);
        }

        if (archive_folder == null) {
            debug("Can't archive email because no archive folder was found in %s", account.to_string());
        } else {
            return yield move_email_async(email_ids, archive_folder.path, cancellable);
        }

        return null;
    }
}
