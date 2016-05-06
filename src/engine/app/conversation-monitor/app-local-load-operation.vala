/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.LocalLoadOperation : ConversationOperation {
    public LocalLoadOperation(ConversationMonitor monitor) {
        base(monitor);
    }
    
    public override async void execute_async() {
        yield monitor.local_load_async();
    }
}
