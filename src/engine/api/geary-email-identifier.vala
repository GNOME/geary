/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2019 Michael Gratton <mike@vee.net>.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A unique identifier for an {@link Email} throughout a Geary {@link Account}.
 *
 * Every Email has an {@link EmailIdentifier}.  Since the Geary engine supports the notion of an
 * Email being located in multiple {@link Folder}s, this identifier can be used to detect these
 * duplicates no matter how it's retrieved -- from any Folder or an Account object (i.e. via
 * search).
 *
 * TODO: EmailIdentifiers may be expanded in the future to include Account information, meaning
 * they will be unique throughout the Geary engine.
 */

public abstract class Geary.EmailIdentifier :
    BaseObject, Gee.Hashable<Geary.EmailIdentifier> {

    /** Base variant type returned by {@link to_variant}. */
    public const string BASE_VARIANT_TYPE = "(yr)";


    /** {@inheritDoc} */
    public abstract uint hash();

    /** {@inheritDoc} */
    public abstract bool equal_to(EmailIdentifier other);

    /**
     * Returns a representation useful for serialisation.
     *
     * This can be used to transmit ids as D-Bus method and GLib
     * Action parameters, and so on.
     *
     * @return a serialised form of this id, that will match the
     * GVariantType given by {@link BASE_VARIANT_TYPE}.
     *
     * @see Account.to_email_identifier
     */
    public abstract GLib.Variant to_variant();

    /**
     * Returns a representation useful for debugging.
     */
    public abstract string to_string();

    /**
     * A comparator for stabilizing sorts.
     *
     * This has no bearing on a "natural" sort order for EmailIdentifiers and shouldn't be used
     * to indicate such.  This is why EmailIdentifier doesn't implement the Comparable interface.
     */
    public virtual int stable_sort_comparator(Geary.EmailIdentifier other) {
        if (this == other)
            return 0;

        return strcmp(to_string(), other.to_string());
    }

    /**
     * A comparator for finding which {@link EmailIdentifier} is earliest in the "natural"
     * sorting of a {@link Folder}'s list.
     *
     * This only applies for {@link Email} which is listed from a Folder; fetching or listing
     * Email from the {@link Account} has no sense of natural ordering.  Also, this should not be
     * used for EmailIdentifiers that originated from different Folders.
     *
     * Implementations should treat messages with no natural ordering (not coming from a
     * Folder) as later than than that do (i.e. returns 1).
     *
     * If both have no natural order, they are considered equal for the purposes of this method;
     * {@link stable_sort_comparator} can be used to deal with that situation.
     *
     * EmailIdentifiers that cannot be compared against this one (i.e. of a different subclass)
     * should return 1 as well.  Generally this means they came from different Folders.
     *
     * @see Folder.list_email_by_id_async
     */
    public abstract int natural_sort_comparator(Geary.EmailIdentifier other);

    /**
     * Sorts the supplied Collection of {@link EmailIdentifier} by their natural sort order.
     *
     * This method uses {@link natural_sort_comparator}, so read its provisions about comparison.
     * In essence, this method should only be used against EmailIdentifiers that originated from
     * the same Folder.
     */
    public static Gee.SortedSet<Geary.EmailIdentifier> sort(Gee.Collection<Geary.EmailIdentifier> ids) {
        Gee.SortedSet<Geary.EmailIdentifier> sorted = new Gee.TreeSet<Geary.EmailIdentifier>(
            (a, b) => {
                int cmp = a.natural_sort_comparator(b);
                if (cmp == 0)
                    cmp = a.stable_sort_comparator(b);

                return cmp;
            });
        sorted.add_all(ids);

        return sorted;
    }

    /**
     * Sorts the supplied Collection of {@link EmailIdentifier} by their natural sort order.
     *
     * This method uses {@link natural_sort_comparator}, so read its provisions about comparison.
     * In essence, this method should only be used against EmailIdentifiers that originated from
     * the same Folder.
     */
    public static Gee.SortedSet<Geary.Email> sort_emails(Gee.Collection<Geary.Email> emails) {
        Gee.SortedSet<Geary.Email> sorted = new Gee.TreeSet<Geary.Email>(
            (a, b) => {
                int cmp = a.id.natural_sort_comparator(b.id);
                if (cmp == 0)
                    cmp = a.id.stable_sort_comparator(b.id);

                return cmp;
            });
        sorted.add_all(emails);

        return sorted;
    }

}
