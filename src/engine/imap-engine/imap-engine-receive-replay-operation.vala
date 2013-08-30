/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.ReceiveReplayOperation : Geary.ImapEngine.ReplayOperation {
    public ReceiveReplayOperation(string name) {
        base (name, ReplayOperation.Scope.LOCAL_ONLY);
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        debug("Warning: ReceiveReplayOperation.replay_remote_async() called");
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override async void backout_local_async() throws Error {
        debug("Warning: ReceiveReplayOperation.backout_local_async() called");
    }
}

