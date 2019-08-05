/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

private class Geary.App.ExternalAppendOperation : BatchOperation<EmailIdentifier> {


    private Geary.Folder folder;


    public ExternalAppendOperation(ConversationMonitor monitor,
                                   Geary.Folder folder,
                                   Gee.Collection<EmailIdentifier> appended_ids) {
        base(monitor, appended_ids);
        this.folder = folder;
    }

    public override async void execute_batch(Gee.Collection<EmailIdentifier> batch)
        throws GLib.Error {
        if (!this.monitor.get_search_folder_blacklist().contains(folder.path) &&
            !this.monitor.conversations.is_empty) {
            debug("Appending %d out of folder message(s) to %s",
                  batch.size,
                  this.folder.to_string());

            yield this.monitor.external_load_by_sparse_id(
                this.folder, batch, Geary.Folder.ListFlags.NONE
            );
        }
    }

}
