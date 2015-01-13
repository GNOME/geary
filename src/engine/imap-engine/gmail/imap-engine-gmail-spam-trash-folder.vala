/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Gmail's Spam and Trash folders support basic operations and removing messages with a traditional
 * IMAP STORE/EXPUNGE operation.
 */

private class Geary.ImapEngine.GmailSpamTrashFolder : MinimalFolder, FolderSupport.Remove,
    FolderSupport.Empty {
    public GmailSpamTrashFolder(GmailAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
    
    public async void remove_email_async(Gee.List<Geary.EmailIdentifier> email_ids,
        Cancellable? cancellable = null) throws Error {
        yield expunge_email_async(email_ids, cancellable);
    }
    
    public async void empty_folder_async(Cancellable? cancellable = null) throws Error {
        yield expunge_all_async(cancellable);
    }
}

