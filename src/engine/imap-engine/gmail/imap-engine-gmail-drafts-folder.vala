/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A draft folder for Gmail.
 *
 * Gmail's drafts folders supports basic operations as well as true
 * removal of messages and creating new ones (IMAP APPEND).
 */
private class Geary.ImapEngine.GmailDraftsFolder :
    MinimalFolder, FolderSupport.Create, FolderSupport.Remove {

    public GmailDraftsFolder(GmailAccount account,
                             ImapDB.Folder local_folder) {
        base(account, local_folder, DRAFTS);
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

    public async void
        remove_email_async(Gee.Collection<EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield GmailFolder.true_remove_email_async(this, email_ids, cancellable);
    }

}
