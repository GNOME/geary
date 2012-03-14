/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * CreateLocalEmailOperation is a common Geary.NonblockingBatchOperation that can be used with
 * Geary.NonblockingBatch.
 *
 * Note that this operation always returns null.  The result of Geary.Sqlite.Folder.create_email_async()
 * is stored in the created property.
 */
private class Geary.CreateLocalEmailOperation : Geary.NonblockingBatchOperation {
    public Geary.Sqlite.Folder folder { get; private set; }
    public Geary.Email email { get; private set; }
    public bool created { get; private set; default = false; }
    
    public CreateLocalEmailOperation(Geary.Sqlite.Folder folder, Geary.Email email) {
        this.folder = folder;
        this.email = email;
    }
    
    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        created = yield folder.create_email_async(email, cancellable);
        
        return null;
    }
}

/**
 * RemoveLocalEmailOperation is a common NonblockingBatchOperation that can be used with
 * NonblockingBatch.
 *
 * Note that this operation always returns null, as Geary.Sqlite.Folder.remove_email_async() has no
 * returned value.
 */
private class Geary.RemoveLocalEmailOperation : Geary.NonblockingBatchOperation {
    public Geary.Sqlite.Folder folder { get; private set; }
    public Geary.EmailIdentifier email_id { get; private set; }
    
    public RemoveLocalEmailOperation(Geary.Sqlite.Folder folder, Geary.EmailIdentifier email_id) {
        this.folder = folder;
        this.email_id = email_id;
    }
    
    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        yield folder.remove_single_email_async(email_id, cancellable);
        
        return null;
    }
}

