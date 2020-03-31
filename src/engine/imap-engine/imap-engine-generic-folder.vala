/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.GenericFolder : MinimalFolder,
    Geary.FolderSupport.Archive,
    Geary.FolderSupport.Remove,
    Geary.FolderSupport.Create,
    Geary.FolderSupport.Empty {

    public GenericFolder(GenericAccount account,
                         ImapDB.Folder local_folder,
                         Folder.SpecialUse use) {
        base (account, local_folder, use);
    }

    public async Geary.Revokable?
        archive_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                            GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        Geary.Folder? archive_folder = null;
        try {
            archive_folder = yield account.get_required_special_folder_async(
                Folder.SpecialUse.ARCHIVE, cancellable
            );
        } catch (Error e) {
            debug("Error looking up archive folder in %s: %s", account.to_string(), e.message);
        }

        if (archive_folder == null) {
            debug("Can't archive email because no archive folder was found in %s", account.to_string());
        } else {
            return yield move_email_async(email_ids, archive_folder.path, cancellable);
        }

        return null;
    }

    public async void
        remove_email_async(Gee.Collection<Geary.EmailIdentifier> email_ids,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        yield expunge_email_async(email_ids, cancellable);
    }

    public async void empty_folder_async(Cancellable? cancellable = null) throws Error {
        yield expunge_all_async(cancellable);
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
}
