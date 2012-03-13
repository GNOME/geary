/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * CreateEmailOperation is a common Geary.NonblockingBatchOperation that can be used with
 * Geary.NonblockingBatch.
 *
 * Note that this operation always returns null.  The result of Geary.Folder.create_email_async()
 * is stored in the created property.
 */
public class Geary.CreateEmailOperation : Geary.NonblockingBatchOperation {
    public Geary.Folder folder { get; private set; }
    public Geary.Email email { get; private set; }
    public bool created { get; private set; default = false; }
    
    public CreateEmailOperation(Geary.Folder folder, Geary.Email email) {
        this.folder = folder;
        this.email = email;
    }
    
    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        created = yield folder.create_email_async(email, cancellable);
        
        return null;
    }
}

/**
 * RemoveEmailOperation is a common NonblockingBatchOperation that can be used with
 * NonblockingBatch.
 *
 * Note that this operation always returns null, as Geary.Folder.remove_email_async() has no returned
 * value.
 */
public class Geary.RemoveEmailOperation : Geary.NonblockingBatchOperation {
    public Geary.Folder folder { get; private set; }
    public Geary.EmailIdentifier email_id { get; private set; }
    
    public RemoveEmailOperation(Geary.Folder folder, Geary.EmailIdentifier email_id) {
        this.folder = folder;
        this.email_id = email_id;
    }
    
    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        yield folder.remove_single_email_async(email_id, cancellable);
        
        return null;
    }
}

