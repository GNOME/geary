/* Copyright 2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The addition of the Geary.FolderSupport.Associations interface to a {@link Geary.Folder}
 * indicates it has special support for organizing its flat list of {@link Geary.Email} into
 * structured {@link Geary.AssociatedEmails}.
 *
 * This interface indicates that the Folder's implementation has an optimized method for building
 * the associations.  Virtual and special folders may not be able to load conversations any faster
 * than {@link ConversationMonitor}, which has a fallback method for generating conversations for
 * Folders that don't support this interface.
 */

public interface Geary.FolderSupport.Associations : Geary.Folder {
    /**
     * List {@link AssociatedEmails} for {@link Email} in the {@link Folder} starting from the
     * specified {@link EmailIdentifier} and traversing down the vector.
     *
     * Like {@link Folder.list_email_by_id_async}, the EmailIdentifier may be null to indicate
     * listing associations from the top of the Folder's vector.  count indicates the number of
     * desired AssociatedEmails to return.  Since Email in a Folder may be associated, the total
     * number of EmailIdentifiers local to this Folder in all AssociatedEmails may be greater than
     * this count.
     *
     * Unlike list_email_by_id_async, however, count may not be negative, i.e. there is no
     * support for walking "up" the email vector.  This may be added later if necessary.
     *
     * initial_id is ''not'' included in the returned collection of AssociatedEmails.  This may also
     * be made an option later, if necessary.
     *
     * primary_email_ids is the collection of EmailIdentifiers that all associations are keyed off
     * of.  It does ''not'' include EmailIdentifiers that are outside of the initial vector range
     * of loaded emails.
     *
     * For example, if the top 20 emails are loaded to generate associations but an email
     * is found deeper in the Folder's vector of emails that is associated with one of the first 20,
     * that EmailIdentifier is ''not'' included in primary_email_ids.  Thus, the lowest email
     * identifier of the returned collection can be used as the initial_id for the next call to
     * this method.
     *
     * already_seen_ids allows for the caller to supply a collection of all previously loaded (seen)
     * EmailIdentifiers from prior calls (either from this method or
     * {@link Account.local_search_associated_emails_async}) indicating that if they are encountered
     * while listing, don't load associations for that identifier.
     *
     * This only lists Email stored in the local store.
     *
     * @see Geary.Folder.find_boundaries_async
     */
    public abstract async Gee.Collection<Geary.AssociatedEmails>? local_list_associated_emails_async(
        Geary.EmailIdentifier? initial_id, int count, Geary.Account.EmailSearchPredicate? predicate,
        Gee.Collection<Geary.EmailIdentifier>? primary_loaded_ids,
        Gee.Collection<Geary.EmailIdentifier>? already_seen_ids, Cancellable? cancellable = null)
        throws Error;
}

