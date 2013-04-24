/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private abstract class Geary.ImapEngine.SendReplayOperation : Geary.ImapEngine.ReplayOperation {
    public SendReplayOperation(string name) {
        base (name, ReplayOperation.Scope.LOCAL_AND_REMOTE);
    }
    
    public SendReplayOperation.only_remote(string name) {
        base (name, ReplayOperation.Scope.REMOTE_ONLY);
    }
}

