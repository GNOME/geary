/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ExternalAppendOperation : ConversationOperation {
    private Geary.Folder folder;
    private Gee.Collection<Geary.EmailIdentifier> appended_ids;
    
    public ExternalAppendOperation(ConversationMonitor monitor, Geary.Folder folder,
        Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        base(monitor);
        this.folder = folder;
        this.appended_ids = appended_ids;
    }
    
    public override async void execute_async() {
        yield monitor.external_append_emails_async(folder, appended_ids);
    }
}
