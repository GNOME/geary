/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Gmail's All Mail folder supports basic operations as well as true removal of emails.
 */

private class Geary.ImapEngine.GmailAllMailFolder : MinimalFolder, FolderSupport.Remove {
    public GmailAllMailFolder(GmailAccount account,
                              ImapDB.Folder local_folder) {
        base(account, local_folder, ALL_MAIL);
    }

    public async void
        remove_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield GmailFolder.true_remove_email_async(this, email_ids, cancellable);
    }
}
