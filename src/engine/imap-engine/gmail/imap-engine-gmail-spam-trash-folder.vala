/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Gmail's Spam and Trash folders support basic operations and
 * removing messages with a traditional IMAP STORE/EXPUNGE operation.
 */
private class Geary.ImapEngine.GmailSpamTrashFolder :
    MinimalFolder,
    FolderSupport.Remove,
    FolderSupport.Empty {

    public GmailSpamTrashFolder(GmailAccount account,
                                ImapDB.Folder local_folder,
                                Folder.SpecialUse use) {
        base(account, local_folder, use);
    }

    public async void
        remove_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield expunge_email_async(email_ids, cancellable);
    }

    public async void empty_folder_async(Cancellable? cancellable = null)
        throws Error {
        yield expunge_all_async(cancellable);
    }

}
