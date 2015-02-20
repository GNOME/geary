/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An immutable representation of all known local {@link Email}s which are associated with one
 * another due to their Message-ID, In-Reply-To, and References headers.
 *
 * This object is free-form and does not impose any ordering or threading on the emails.  It is
 * also not updated as new email arrives and email is removed.
 *
 * @see Account.local_search_associated_emails_async
 */

public class Geary.AssociatedEmails : BaseObject {
    /**
     * All associated {@link Email}s.
     */
    public Gee.Collection<Geary.Email> emails { get; private set; }
    
    /**
     * All known {@link FolderPath}s for each {@link Email}.
     *
     * null if the Email is currently associated with no {@link Folder}s.
     */
    public Gee.MultiMap<Geary.Email, Geary.FolderPath?> known_paths { get; private set; }
    
    public AssociatedEmails() {
        emails = new Gee.ArrayList<Email>();
        known_paths = new Gee.HashMultiMap<Email, FolderPath?>();
    }
    
    public void add(Geary.Email email, Gee.Collection<Geary.FolderPath?> paths) {
        emails.add(email);
        foreach (FolderPath path in paths)
            known_paths.set(email, path);
    }
}

