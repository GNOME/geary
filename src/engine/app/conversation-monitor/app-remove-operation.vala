/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.RemoveOperation : ConversationOperation {

    private Geary.Folder source_folder;
    private Gee.Collection<Geary.EmailIdentifier> removed_ids;

    public RemoveOperation(ConversationMonitor monitor,
                           Geary.Folder source_folder,
                           Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        base(monitor);
        this.source_folder = source_folder;
        this.removed_ids = removed_ids;
    }

    public override async void execute_async() {
        yield monitor.remove_emails_async(this.source_folder, this.removed_ids);
    }

}
