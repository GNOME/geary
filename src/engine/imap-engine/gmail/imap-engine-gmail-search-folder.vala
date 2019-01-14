/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Gmail-specific SearchFolder implementation.
 */
private class Geary.ImapEngine.GmailSearchFolder : ImapDB.SearchFolder {

    private Geary.App.EmailStore email_store;

    public GmailSearchFolder(Geary.Account account, FolderRoot root) {
        base (account, root);

        this.email_store = new Geary.App.EmailStore(account);
    }

    public override async void
        remove_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        Geary.Folder? trash_folder = null;
        try {
            trash_folder = yield account.get_required_special_folder_async(
                Geary.SpecialFolderType.TRASH, cancellable
            );
        } catch (Error e) {
            debug("Error looking up trash folder in %s: %s",
                  account.to_string(), e.message);
        }

        if (trash_folder == null) {
            debug("Can't remove email from search folder because no trash folder was found in %s",
                  account.to_string());
        } else {
            // Copying to trash from one folder is all that's required in Gmail
            // to fully trash the message.
            yield this.email_store.copy_email_async(
                email_ids, trash_folder.path, cancellable
            );
        }
    }
}
