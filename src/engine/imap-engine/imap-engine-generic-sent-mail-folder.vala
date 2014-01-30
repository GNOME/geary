/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

// Sent Mail generally is the same as other mail folders, but it doesn't support key features,
// like archiving (since sent messages are in the archive).  Instead, it supports appending.
//
// Service-specific accounts can use this or subclass it for further customization

private class Geary.ImapEngine.GenericSentMailFolder : GenericFolder, Geary.FolderSupport.Create {
    public GenericSentMailFolder(GenericAccount account, Imap.Account remote, ImapDB.Account local,
        ImapDB.Folder local_folder, SpecialFolderType special_folder_type) {
        base (account, remote, local, local_folder, special_folder_type);
    }
    
    public new async Geary.EmailIdentifier? create_email_async(RFC822.Message message, Geary.EmailFlags? flags,
        DateTime? date_received, Geary.EmailIdentifier? id, Cancellable? cancellable) throws Error {
        return yield base.create_email_async(message, flags, date_received, id, cancellable);
    }
}
