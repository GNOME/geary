/* Copyright 2013-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapEngine.CreateEmail : Geary.ImapEngine.SendReplayOperation {
    public Geary.EmailIdentifier? created_id { get; private set; default = null; }
    
    private MinimalFolder engine;
    private RFC822.Message rfc822;
    private Geary.EmailFlags? flags;
    private DateTime? date_received;
    private Cancellable? cancellable;
    
    public CreateEmail(MinimalFolder engine, RFC822.Message rfc822, Geary.EmailFlags? flags,
        DateTime? date_received, Cancellable? cancellable) {
        base.only_remote("CreateEmail");
        
        this.engine = engine;
        
        this.rfc822 = rfc822;
        this.flags = flags;
        this.date_received = date_received;
        this.cancellable = cancellable;
    }
    
    public override async ReplayOperation.Status replay_local_async() throws Error {
        return ReplayOperation.Status.CONTINUE;
    }
    
    public override void notify_remote_removed_ids(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override void get_ids_to_be_remote_removed(Gee.Collection<ImapDB.EmailIdentifier> ids) {
    }
    
    public override async void backout_local_async() throws Error {
    }
    
    public override string describe_state() {
        return "";
    }
    
    public override async ReplayOperation.Status replay_remote_async() throws Error {
        // Deal with cancellable manually since create_email_async cannot be cancelled.
        if (cancellable.is_cancelled())
            throw new IOError.CANCELLED("CreateEmail op cancelled immediately");
        
        // use IMAP APPEND command on remote folders, which doesn't require opening a folder
        created_id = yield engine.remote_folder.create_email_async(rfc822, flags, date_received);
        
        // If the user cancelled the operation, we need to wipe the new message to keep this
        // operation atomic.
        if (cancellable.is_cancelled()) {
            yield engine.remote_folder.remove_email_async(
                new Imap.MessageSet.uid(((ImapDB.EmailIdentifier) created_id).uid), null);
            
            throw new IOError.CANCELLED("CreateEmail op cancelled after create");
        }
        
        // TODO: need to prevent gaps that may occur here
        Geary.Email created = new Geary.Email(created_id);
        Gee.Map<Geary.Email, bool> results = yield engine.local_folder.create_or_merge_email_async(
            Geary.iterate<Geary.Email>(created).to_array_list(), cancellable);
        if (results.size > 0)
            created_id = Collection.get_first<Geary.Email>(results.keys).id;
        else
            created_id = null;
        
        return ReplayOperation.Status.COMPLETED;
    }
}
