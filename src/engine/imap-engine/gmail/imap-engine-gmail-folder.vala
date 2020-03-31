/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GmailFolder : MinimalFolder, FolderSupport.Archive,
    FolderSupport.Create, FolderSupport.Remove {
    public GmailFolder(GmailAccount account,
                       ImapDB.Folder local_folder,
                       Folder.SpecialUse use) {
        base (account, local_folder, use);
    }

    public new async EmailIdentifier?
        create_email_async(RFC822.Message rfc822,
                           EmailFlags? flags,
                           DateTime? date_received,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return yield base.create_email_async(
            rfc822, flags, date_received, cancellable
        );
    }

    public async Geary.Revokable?
        archive_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                            GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        // Use move_email_async("All Mail") here; Gmail will do the right thing and report
        // it was copied with the pre-existing All Mail UID (in other words, no actual copy is
        // performed).  This allows for undoing an archive with the same code path as a move.
        Geary.Folder? all_mail = account.get_special_folder(ALL_MAIL);
        if (all_mail != null)
            return yield move_email_async(email_ids, all_mail.path, cancellable);

        // although this shouldn't happen, fall back on our traditional archive, which is simply
        // to remove the message from this label
        message("%s: Unable to perform revokable archive: All Mail not found", to_string());
        yield expunge_email_async(email_ids, cancellable);

        return null;
    }

    public async void
        remove_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
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
    public static async void
        true_remove_email_async(MinimalFolder folder,
                                Gee.Collection<Geary.EmailIdentifier> email_ids,
                                GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Get path to Trash folder
        Geary.Folder? trash = folder.account.get_special_folder(TRASH);
        if (trash == null)
            throw new EngineError.NOT_FOUND("%s: Trash folder not found for removal", folder.to_string());

        // Copy to Trash, collect UIDs (note that copying to Trash is like a move; the copied
        // messages are removed from all labels)
        Gee.Set<Imap.UID>? uids = yield folder.copy_email_uids_async(email_ids, trash.path, cancellable);
        if (uids == null || uids.size == 0) {
            GLib.debug("%s: Can't true-remove %d emails, no COPYUIDs returned", folder.to_string(),
                email_ids.size);

            return;
        }

        // For speed reasons, use a standalone Imap.Folder object to delete moved emails; this is a
        // separate connection and is not synchronized with the database, but also avoids a full
        // folder normalization, which can be a heavyweight operation
        GenericAccount account = (GenericAccount) folder.account;
        Imap.FolderSession imap_trash = yield account.claim_folder_session(
            trash.path, cancellable
        );
        try {
            yield imap_trash.remove_email_async(Imap.MessageSet.uid_sparse(uids), cancellable);
        } finally {
            yield account.release_folder_session(imap_trash);
        }

        GLib.debug("%s: Successfully true-removed %d/%d emails", folder.to_string(), uids.size,
            email_ids.size);
    }
}
