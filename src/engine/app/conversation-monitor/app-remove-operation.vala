/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.RemoveOperation : ConversationOperation {
    private Gee.Collection<Geary.EmailIdentifier> removed_ids;
    
    public RemoveOperation(ConversationMonitor monitor, Gee.Collection<Geary.EmailIdentifier> removed_ids) {
        base(monitor);
        this.removed_ids = removed_ids;
    }
    
    public override async void execute_async() {
        yield monitor.remove_emails_async(removed_ids);
    }
}
