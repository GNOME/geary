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
    public Gee.Collection<Geary.EmailIdentifier> email_ids { get; private set; }
    
    /**
     * All known {@link FolderPath}s for each {@link EmailIdentifier}.
     *
     * null if the Email is currently associated with no {@link Folder}s.
     */
    public Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath?> known_paths { get; private set; }
    
    public AssociatedEmails() {
        email_ids = new Gee.ArrayList<EmailIdentifier>();
        known_paths = new Gee.HashMultiMap<Email, FolderPath?>();
    }
    
    public void add(Geary.EmailIdentifier email_id, Gee.Collection<Geary.FolderPath?> paths) {
        email_ids.add(email_id);
        foreach (FolderPath path in paths)
            known_paths.set(email_id, path);
    }
}

