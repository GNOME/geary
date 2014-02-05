/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ReseedOperation : ConversationOperation {
    private string why;
    
    public ReseedOperation(ConversationMonitor monitor, string why) {
        base(monitor);
        this.why = why;
    }
    
    public override async void execute_async() {
         yield monitor.reseed_async(why);
    }
}
