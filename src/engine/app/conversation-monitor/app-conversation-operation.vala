/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.App.ConversationOperation : BaseObject {
    protected weak ConversationMonitor? monitor = null;
    
    public ConversationOperation(ConversationMonitor? monitor) {
        this.monitor = monitor;
    }
    
    public abstract async void execute_async();
}
