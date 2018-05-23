/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */


/**
 * A replay operation for a user-initiated operation.
 */
private abstract class Geary.ImapEngine.SendReplayOperation : Geary.ImapEngine.ReplayOperation {
    protected SendReplayOperation(string name, ReplayOperation.OnError on_remote_error = OnError.THROW) {
        base (name, ReplayOperation.Scope.LOCAL_AND_REMOTE, on_remote_error);
    }

    protected SendReplayOperation.only_local(string name, ReplayOperation.OnError on_remote_error = OnError.THROW) {
        base (name, ReplayOperation.Scope.LOCAL_ONLY, on_remote_error);
    }

    protected SendReplayOperation.only_remote(string name, ReplayOperation.OnError on_remote_error = OnError.THROW) {
        base (name, ReplayOperation.Scope.REMOTE_ONLY, on_remote_error);
    }

    public override void notify_remote_removed_position(Imap.SequenceNumber removed) {
        // we've worked very hard to keep positional addressing out of the SendReplayOperations
    }

}
