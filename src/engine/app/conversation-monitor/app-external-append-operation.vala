/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ExternalAppendOperation : ConversationOperation {

    private Geary.Folder folder;
    private Gee.Collection<Geary.EmailIdentifier> appended_ids;

    public ExternalAppendOperation(ConversationMonitor monitor,
                                   Geary.Folder folder,
                                   Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        base(monitor);
        this.folder = folder;
        this.appended_ids = appended_ids;
    }

    public override async void execute_async() throws Error {
        if (!this.monitor.get_search_folder_blacklist().contains(folder.path) &&
            !this.monitor.conversations.is_empty) {
            debug("%d out of folder message(s) appended to %s, fetching to add to conversations...",
                  this.appended_ids.size,
                  this.folder.to_string());

            yield this.monitor.external_load_by_sparse_id(
                this.folder, this.appended_ids, Geary.Folder.ListFlags.NONE
            );
        }
    }

}
