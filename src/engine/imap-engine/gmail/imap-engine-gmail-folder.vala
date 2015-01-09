/* Copyright 2012-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GmailFolder : MinimalFolder, FolderSupport.Archive,
    FolderSupport.Create, FolderSupport.Remove {
    public GmailFolder(GmailAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
    
    public new async Geary.EmailIdentifier? create_email_async(
        RFC822.Message rfc822, Geary.EmailFlags? flags, DateTime? date_received,
        Geary.EmailIdentifier? id, Cancellable? cancellable = null) throws Error {
        return yield base.create_email_async(rfc822, flags, date_received, id, cancellable);
    }
    
    public async void archive_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        yield expunge_email_async(email_ids, cancellable);
    }
    
    public async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        yield true_remove_email_async(this, email_ids, cancellable);
    }
    
    /**
     * Truly removes an email from Gmail by moving it to the Trash and then deleting it from the
     * Trash.
     *
     * TODO: Because the steps after copy don't go through the ReplayQueue, they won't be recorded
     * in the database directly.  This is important when/if offline mode is coded, as if there's
     * no connection (or the connection dies) there's no record that Geary needs to perform the
     * final remove when a connection is reestablished.
     */
    public static async void true_remove_email_async(MinimalFolder folder,
        Gee.List<Geary.EmailIdentifier> email_ids, Cancellable? cancellable) throws Error {
        // Get path to Trash folder
        Geary.Folder? trash = folder.account.get_special_folder(SpecialFolderType.TRASH);
        if (trash == null)
            throw new EngineError.NOT_FOUND("%s: Trash folder not found for removal", folder.to_string());
        
        // Copy to Trash, collect UIDs (note that copying to Trash is like a move; the copied
        // messages are removed from all labels)
        Gee.Set<Imap.UID>? uids = yield folder.copy_email_uids_async(email_ids, trash.path, cancellable);
        if (uids == null || uids.size == 0) {
            debug("%s: Can't true-remove %d emails, no COPYUIDs returned", folder.to_string(),
                email_ids.size);
            
            return;
        }
        
        // For speed reasons, use a detached Imap.Folder object to delete moved emails; this is a
        // separate connection and is not synchronized with the database, but also avoids a full
        // folder normalization, which can be a heavyweight operation
        Imap.Folder imap_trash = yield ((GenericAccount) folder.account).fetch_detached_folder_async(
            trash.path, cancellable);
        
        yield imap_trash.open_async(cancellable);
        try {
            yield imap_trash.remove_email_async(Imap.MessageSet.uid_sparse(uids), cancellable);
        } finally {
            try {
                // don't use cancellable, need to close this connection no matter what
                yield imap_trash.close_async(null);
            } catch (Error err) {
                // ignored
            }
        }
        
        debug("%s: Successfully true-removed %d/%d emails", folder.to_string(), uids.size,
            email_ids.size);
    }
}

