/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.ExpungeFolder : Geary.ImapEngine.SendReplayOperation {
    private GenericFolder owner;
    private Cancellable? cancellable;
    
    public ExpungeFolder(GenericFolder owner, Cancellable? cancellable) {
        base.only_remote("ExpungeFolder");
        
        this.owner = owner;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async void backout_local_async() throws Error {
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        yield owner.remote_folder.expunge_async(cancellable);
        
        return ReplayOperation.Status.COMPLETED;
    }
    
    public override string describe_state() {
        return "";
    }
}
