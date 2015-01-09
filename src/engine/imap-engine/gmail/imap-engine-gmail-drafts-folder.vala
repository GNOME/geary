/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Gmail's Drafts folder supports basic operations as well as true removal of messages and creating
 * new ones (IMAP APPEND).
 */

private class Geary.ImapEngine.GmailDraftsFolder : MinimalFolder, FolderSupport.Create,
    FolderSupport.Remove {
    public GmailDraftsFolder(GmailAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
    
    public new async Geary.EmailIdentifier? create_email_async(
        RFC822.Message rfc822, Geary.EmailFlags? flags, DateTime? date_received,
        Geary.EmailIdentifier? id, Cancellable? cancellable = null) throws Error {
        return yield base.create_email_async(rfc822, flags, date_received, id, cancellable);
    }
    
    public async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        yield GmailFolder.true_remove_email_async(this, email_ids, cancellable);
    }
}
