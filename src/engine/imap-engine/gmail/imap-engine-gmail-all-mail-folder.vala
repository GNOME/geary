/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Gmail's All Mail folder supports basic operations as well as true removal of emails.
 */

private class Geary.ImapEngine.GmailAllMailFolder : MinimalFolder, FolderSupport.Remove {
    public GmailAllMailFolder(GmailAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
    
    public async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        yield GmailFolder.true_remove_email_async(this, email_ids, cancellable);
    }
}
