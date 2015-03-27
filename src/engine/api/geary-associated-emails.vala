/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An immutable representation of all known local {@link EmailIdentifier}s which are associated with
 * one another due to their Message-ID, In-Reply-To, and References headers.
 *
 * This object is free-form and does not impose any ordering or threading on the emails.  It is
 * also not updated as new email arrives and email is removed.  Treat it as a snapshot of the
 * existing state of the local mail store.
 *
 * @see Account.local_search_associated_emails_async
 */

public class Geary.AssociatedEmails : BaseObject {
    /**
     * All associated {@link EmailIdentifier}s.
     */
    public Gee.Set<Geary.EmailIdentifier> email_ids { get; private set; }
    
    /**
     * All associated {@link Email}s with {@link required_fields} fulfilled, if possible.
     *
     * It's possible for the Email to have ''more'' than the required fields as well.
     */
    public Gee.Map<Geary.EmailIdentifier, Geary.Email> emails { get; private set; }
    
    /**
     * All known {@link FolderPath}s for each {@link EmailIdentifier}.
     *
     * null if the Email is currently associated with no {@link Folder}s.
     */
    public Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath?> known_paths { get; private set; }
    
    /**
     * The required {@link Geary.Email.Field}s specified when the {@link AssociatedEmails} was
     * generated.
     */
    public Geary.Email.Field required_fields { get; private set; }
    
    public AssociatedEmails(Geary.Email.Field required_fields) {
        this.required_fields = required_fields;
        
        email_ids = new Gee.HashSet<EmailIdentifier>();
        emails = new Gee.HashMap<EmailIdentifier, Email>();
        known_paths = new Gee.HashMultiMap<Email, FolderPath?>();
    }
    
    /**
     * Add the {@link Email} to the set of {@link AssociatedEmails}.
     *
     * No checking is performed to ensure the Email fulfills {@link required_fields}.
     */
    public void add(Geary.Email email, Gee.Collection<Geary.FolderPath?> paths) {
        email_ids.add(email.id);
        emails.set(email.id, email);
        foreach (FolderPath path in paths)
            known_paths.set(email.id, path);
    }
}

