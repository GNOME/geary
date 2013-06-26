/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.App.ConversationOperation : BaseObject {
    protected ConversationMonitor? monitor = null;
    
    public ConversationOperation(ConversationMonitor? monitor) {
        this.monitor = monitor;
    }
    
    public abstract async void execute_async();
}
