/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ExternalRemoveOperation : ConversationOperation {
    private Geary.FolderPath path;
    private Gee.Collection<Geary.EmailIdentifier> removed_ids;
    
    public ExternalRemoveOperation(ConversationMonitor monitor, Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        base(monitor);
        
        path = folder.path;
        this.removed_ids = removed_ids;
    }
    
    public override async void execute_async() {
        yield monitor.remove_emails_async(path, removed_ids);
    }
}
