/* Copyright 2011-2013 Yorba Foundation
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

private class Geary.ImapEngine.CreateLocalEmailOperation : Geary.Nonblocking.BatchOperation {
    public ImapDB.Folder folder { get; private set; }
    public Gee.Collection<Geary.Email> emails { get; private set; }
    public Geary.Email.Field required_fields { get; private set; }
    // Returns the result of ImapDB.Folder.create_or_merge_email_async()
    // Will be non-null after successful execution
    public Gee.Map<Geary.Email, bool>? created { get; private set; default = null; }
    // Map of the created/merged email with one fulfilling all required_fields
    // Will be non-null after successful execution
    public Gee.Map<Geary.Email, Geary.Email>? merged { get; private set; default = null; }
    
    public CreateLocalEmailOperation(ImapDB.Folder folder, Gee.Collection<Geary.Email> emails,
        Geary.Email.Field required_fields) {
        this.folder = folder;
        this.emails = emails;
        this.required_fields = required_fields;
    }
    
    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        created = yield folder.create_or_merge_email_async(emails, cancellable);
        
        merged = new Gee.HashMap<Geary.Email, Geary.Email>();
        foreach (Geary.Email email in emails) {
            if (email.fields.fulfills(required_fields)) {
                merged.set(email, email);
            } else {
                try {
                    Geary.Email merged_email = yield folder.fetch_email_async(
                        (ImapDB.EmailIdentifier) email.id, required_fields,
                        ImapDB.Folder.ListFlags.NONE, cancellable);
                    merged.set(email, merged_email);
                } catch (Error err) {
                    debug("Unable to fetch merged email for %s: %s", email.id.to_string(), err.message);
                }
            }
        }
        
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

private class Geary.ImapEngine.RemoveLocalEmailOperation : Geary.Nonblocking.BatchOperation {
    public ImapDB.Folder folder { get; private set; }
    public Gee.Collection<Geary.EmailIdentifier> email_ids { get; private set; }
    
    public RemoveLocalEmailOperation(ImapDB.Folder folder, Gee.Collection<Geary.EmailIdentifier> email_ids) {
        this.folder = folder;
        this.email_ids = email_ids;
    }
    
    public override async Object? execute_async(Cancellable? cancellable) throws Error {
        yield folder.detach_multiple_emails_async((Gee.Collection<ImapDB.EmailIdentifier>) email_ids, cancellable);
        
        return null;
    }
}

