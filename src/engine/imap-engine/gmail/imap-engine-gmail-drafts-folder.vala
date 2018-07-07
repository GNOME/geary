/* Copyright 2016 Software Freedom Conservancy Inc.
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
    public GmailDraftsFolder(GmailAccount account,
                             ImapDB.Folder local_folder,
                             SpecialFolderType special_folder_type) {
        base (account, local_folder, special_folder_type);
    }

    public new async Geary.EmailIdentifier? create_email_async(
        RFC822.Message rfc822, Geary.EmailFlags? flags, DateTime? date_received,
        Geary.EmailIdentifier? id, Cancellable? cancellable = null) throws Error {
        return yield base.create_email_async(rfc822, flags, date_received, id, cancellable);
    }

    public async void remove_email_async(
        Gee.Collection<Geary.EmailIdentifier> email_ids,
        GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield GmailFolder.true_remove_email_async(this, email_ids, cancellable);
    }
}
