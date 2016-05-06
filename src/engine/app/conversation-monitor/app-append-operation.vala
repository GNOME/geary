/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.AppendOperation : ConversationOperation {
    private Gee.Collection<Geary.EmailIdentifier> appended_ids;
    
    public AppendOperation(ConversationMonitor monitor, Gee.Collection<Geary.EmailIdentifier> appended_ids) {
        base(monitor);
        this.appended_ids = appended_ids;
    }
    
    public override async void execute_async() {
        yield monitor.append_emails_async(appended_ids);
    }
}
