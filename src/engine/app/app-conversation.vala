/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.App.Conversation : BaseObject {
    /**
     * Specify the ordering of {@link Email} returned by various accessors.
     *
     * Note that sorting in {@link Conversation} is done by the RFC822 Date: header (i.e.
     * {@link Email.date}) and not the date received (i.e. {@link EmailProperties.date_received}).
     */
    public enum Ordering {
        NONE,
        SENT_DATE_ASCENDING,
        SENT_DATE_DESCENDING,
        RECV_DATE_ASCENDING,
        RECV_DATE_DESCENDING
    }

    /**
     * Specify the location of the {@link Email} in relation to the base folder being monitored
     * by the {@link Conversation}'s {@link ConversationMonitor}.
     *
     * IN_FOLDER represents Email that is found in the Folder the ConversationMonitor is
     * monitoring.  OUT_OF_FOLDER means the Email is located elsewhere in the {@link Account}.
     *
     * Some methods honor IN_FOLDER_OUT_OF_FOLDER and OUT_OF_FOLDER_IN_FOLDER.  These represent
     * preferences for finding an Email.  The first (IN_FOLDER / OUT_OF_FOLDER) is searched.  If
     * an Email is not found in that location, the other criteria is used.
     */
    public enum Location {
        IN_FOLDER,
        OUT_OF_FOLDER,
        IN_FOLDER_OUT_OF_FOLDER,
        OUT_OF_FOLDER_IN_FOLDER,
        ANYWHERE
    }

    private static int next_convnum = 0;

    /** Folder from which the conversation originated. */
    public Folder base_folder { get; private set; }

    /** Cache of paths associated with each email */
    internal Gee.HashMultiMap<Geary.EmailIdentifier,Geary.FolderPath> path_map {
        get;
        private set;
        default = new Gee.HashMultiMap< Geary.EmailIdentifier,Geary.FolderPath>();
    }

    private Gee.HashMultiSet<RFC822.MessageID> message_ids = new Gee.HashMultiSet<RFC822.MessageID>();

    private int convnum;

    private Gee.HashMap<EmailIdentifier, Email> emails = new Gee.HashMap<EmailIdentifier, Email>();

    // this isn't ideal but the cost of adding an email to multiple sorted sets once versus
    // the number of times they're accessed makes it worth it
    private Gee.SortedSet<Email> sent_date_ascending = new Gee.TreeSet<Email>(
        Geary.Email.compare_sent_date_ascending);
    private Gee.SortedSet<Email> sent_date_descending = new Gee.TreeSet<Email>(
        Geary.Email.compare_sent_date_descending);
    private Gee.SortedSet<Email> recv_date_ascending = new Gee.TreeSet<Email>(
        Geary.Email.compare_recv_date_ascending);
    private Gee.SortedSet<Email> recv_date_descending = new Gee.TreeSet<Email>(
        Geary.Email.compare_recv_date_descending);

    /**
     * Fired when email has been added to this conversation.
     */
    public signal void appended(Geary.Email email);

    /**
     * Fired when email has been trimmed from this conversation.
     */
    public signal void trimmed(Geary.Email email);

    /**
     * Fired when the flags of an email in this conversation have changed.
     */
    public signal void email_flags_changed(Geary.Email email);


    /**
     * Constructs a conversation relative to the given base folder.
     */
    internal Conversation(Geary.Folder base_folder) {
        this.convnum = Conversation.next_convnum++;
        this.base_folder = base_folder;
    }

    /**
     * Returns the number of emails in the conversation.
     */
    public int get_count() {
        return emails.size;
    }

    /**
     * Returns the number of emails in the conversation in a particular folder.
     */
    public uint get_count_in_folder(FolderPath path) {
        uint count = 0;
        foreach (Geary.EmailIdentifier id in this.path_map.get_keys()) {
            if (path in this.path_map.get(id)) {
                count++;
            }
        }
        return count;
    }

    /**
     * Returns true if *any* message in the conversation is unread.
     */
    public bool is_unread() {
        return has_flag(Geary.EmailFlags.UNREAD);
    }

    /**
     * Returns true if any message in the conversation is not unread.
     */
    public bool has_any_read_message() {
        return is_missing_flag(Geary.EmailFlags.UNREAD);
    }

    /**
     * Returns true if *any* message in the conversation is flagged.
     */
    public bool is_flagged() {
        return has_flag(Geary.EmailFlags.FLAGGED);
    }

    /**
     * Determines if the conversation contains un-deleted email messages.
     */
    public bool has_any_non_deleted_email() {
        return traverse(this.emails.values).any(e => !e.email_flags.is_deleted());
    }

    /**
     * Returns the earliest (first sent) email in the Conversation.
     *
     * Note that here, sent denotes the value of the Date header, not
     * being contained in the Sent folder.
     */
    public Email?
        get_earliest_sent_email(Location location,
                                Gee.Collection<FolderPath>? blacklist = null) {
        return get_single_email(Ordering.SENT_DATE_ASCENDING, location, blacklist);
    }

    /**
     * Returns the latest (most recently sent) email in the Conversation.
     *
     * Note that here, sent denotes the value of the Date header, not
     * being contained in the Sent folder.
     */
    public Email?
        get_latest_sent_email(Location location,
                              Gee.Collection<FolderPath>? blacklist = null) {
        return get_single_email(Ordering.SENT_DATE_DESCENDING, location);
    }

    /**
     * Returns the earliest (first received) email in the Conversation.
     */
    public Email?
        get_earliest_recv_email(Location location,
                                Gee.Collection<FolderPath>? blacklist = null) {
        return get_single_email(Ordering.RECV_DATE_ASCENDING, location);
    }

    /**
     * Returns the latest (most recently received) email in the Conversation.
     */
    public Email?
        get_latest_recv_email(Location location,
                              Gee.Collection<FolderPath>? blacklist = null) {
        return get_single_email(Ordering.RECV_DATE_DESCENDING, location);
    }

    public Gee.Collection<Email>
        get_emails_flagged_for_deletion(Location location,
                                        Gee.Collection<FolderPath>? blacklist = null) {
        Gee.Collection<Email> emails = get_emails(Ordering.NONE, location, blacklist, false);
        Iterable<Email> filtered = traverse<Email>(emails);
        return filtered.filter(
            (e) => e.email_flags.is_deleted()
        ).to_array_list();
    }

    /**
     * Returns the conversation's email, possibly sorted and filtered.
     *
     * {@link Location.IN_FOLDER} and {@link Location.OUT_OF_FOLDER} are the
     * only preferences honored; the others ({@link Location.IN_FOLDER_OUT_OF_FOLDER},
     * {@link Location.IN_FOLDER_OUT_OF_FOLDER}, and {@link Location.ANYWHERE}
     * are all treated as ANYWHERE.
     */
    public Gee.List<Email>
        get_emails(Ordering ordering,
                   Location location = Location.ANYWHERE,
                   Gee.Collection<FolderPath>? blacklist = null,
                   bool filter_deleted = true) {
        Gee.Collection<Email> email;
        switch (ordering) {
            case Ordering.SENT_DATE_ASCENDING:
                email = sent_date_ascending;
            break;

            case Ordering.SENT_DATE_DESCENDING:
                email = sent_date_descending;
            break;

            case Ordering.RECV_DATE_ASCENDING:
                email = recv_date_ascending;
            break;

            case Ordering.RECV_DATE_DESCENDING:
                email = recv_date_descending;
            break;

            case Ordering.NONE:
                email = emails.values;
            break;

            default:
                assert_not_reached();
        }

        Iterable<Email> filtered = traverse<Email>(email);
        switch (location) {
        case Location.IN_FOLDER:
            filtered = filtered.filter((e) => is_in_base_folder(e.id));
            break;

        case Location.OUT_OF_FOLDER:
            filtered = filtered.filter((e) => !is_in_base_folder(e.id));
            break;

        default:
            // Nothing to do
            break;
        }

        // Filter emails waiting to be expunged (\DELETED)
        if (filter_deleted) {
            filtered = filtered.filter(
                (e) => (e.email_flags != null) ? !e.email_flags.is_deleted() : true
            );
        }

        if (blacklist != null && !blacklist.is_empty) {
            if (blacklist.size == 1) {
                FolderPath blacklist_path =
                    traverse<FolderPath>(blacklist).first();
                filtered = filtered.filter(
                    (e) => !this.path_map.get(e.id).contains(blacklist_path)
                );
            } else {
                filtered = filtered.filter(
                    (e) => this.path_map.get(e.id).any_match(
                        (p) => !blacklist.contains(p)
                    )
                );
            }
        }

        return filtered.to_array_list();
    }

    /**
     * Determines if the given id is in the conversation's base folder.
     */
    public bool is_in_base_folder(Geary.EmailIdentifier id) {
        Gee.Collection<Geary.FolderPath>? paths = this.path_map.get(id);
        return (paths != null && paths.contains(this.base_folder.path));
    }

    /**
     * Determines if the given id is in the conversation's base folder.
     */
    public uint get_folder_count(Geary.EmailIdentifier id) {
        Gee.Collection<Geary.FolderPath>? paths = this.path_map.get(id);
        uint count = 0;
        if (paths != null) {
            count = paths.size;
        }
        return count;
    }

    /**
     * Determines if an email with the give id exists in the conversation.
     */
    public bool contains_email_by_id(EmailIdentifier id) {
        return emails.has_key(id);
    }

    /**
     * Returns the email associated with the EmailIdentifier, if it exists.
     */
    public Geary.Email? get_email_by_id(EmailIdentifier id) {
        return emails.get(id);
    }

    /**
     * Returns all EmailIdentifiers in the conversation, unsorted.
     */
    public Gee.Collection<Geary.EmailIdentifier> get_email_ids() {
        return emails.keys;
    }

    /**
     * Return all Message IDs associated with the conversation.
     */
    public Gee.Collection<RFC822.MessageID> get_message_ids() {
        // Turn into a HashSet first, so we don't return duplicates.
        Gee.HashSet<RFC822.MessageID> ids = new Gee.HashSet<RFC822.MessageID>();
        ids.add_all(message_ids);
        return ids;
    }

    /**
     * Returns a string representation for debugging.
     */
    public string to_string() {
        return "[#%d] (%d emails)".printf(convnum, emails.size);
    }

    /**
     * Add the email to the conversation if not already present.
     *
     * The value of `known_paths` should contain all the known {@link
     * FolderPath} instances this email is contained within.
     *
     * Returns if the email was added, else false if already present
     * and only `known_paths` were merged.
     */
    internal bool add(Email email, Gee.Collection<Geary.FolderPath> known_paths) {
        // Add the known paths to the path map regardless of whether
        // the email is already in the conversation or not, so that it
        // remains complete
        foreach (Geary.FolderPath path in known_paths)
            this.path_map.set(email.id, path);

        bool added = false;
        if (!emails.has_key(email.id)) {
            this.emails.set(email.id, email);
            this.sent_date_ascending.add(email);
            this.sent_date_descending.add(email);
            this.recv_date_ascending.add(email);
            this.recv_date_descending.add(email);

            Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
            if (ancestors != null)
                message_ids.add_all(ancestors);

            appended(email);
            added = true;
        }
        return added;
    }

    /**
     * Unconditionally removes an email from the conversation.
     *
     * Returns all Message-IDs that should be removed as result of
     * removing this message, or `null` if none were removed.
     */
    internal Gee.Set<RFC822.MessageID>? remove(Email email) {
        Gee.Set<RFC822.MessageID>? removed_ids = null;

        if (emails.unset(email.id)) {
            this.sent_date_ascending.remove(email);
            this.sent_date_descending.remove(email);
            this.recv_date_ascending.remove(email);
            this.recv_date_descending.remove(email);
            this.path_map.remove_all(email.id);

            Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
            if (ancestors != null) {
                removed_ids = new Gee.HashSet<RFC822.MessageID>();
                foreach (RFC822.MessageID ancestor_id in ancestors) {
                    // if remove() changes set (i.e. it was present) but no longer present, that
                    // means the ancestor_id was the last one and is formally removed
                    if (message_ids.remove(ancestor_id) &&
                        !message_ids.contains(ancestor_id)) {
                        removed_ids.add(ancestor_id);
                    }
                }

                if (removed_ids.size == 0) {
                    removed_ids = null;
                }
            }


            trimmed(email);
        }

        return removed_ids;
    }

    /**
     * Removes the target path from the known set for the given id.
     */
    internal void remove_path(Geary.EmailIdentifier id, FolderPath path) {
        this.path_map.remove(id, path);
    }

    private Geary.Email?
        get_single_email(Ordering ordering, Location location,
                         Gee.Collection<Geary.FolderPath>? blacklist = null) {
        // note that the location-ordering preferences are treated as
        // ANYWHERE by get_emails()
        Gee.Collection<Geary.Email> all = get_emails(
            ordering, location, blacklist
        );
        if (all.size == 0) {
            return null;
        }

        // Because IN_FOLDER_OUT_OF_FOLDER and OUT_OF_FOLDER_IN_FOLDER
        // are treated as ANYWHERE, have to do our own filtering
        switch (location) {
            case Location.IN_FOLDER:
            case Location.OUT_OF_FOLDER:
            case Location.ANYWHERE:
                return traverse<Email>(all).first();

            case Location.IN_FOLDER_OUT_OF_FOLDER:
                Geary.Email? found = traverse<Email>(all)
                    .first_matching((email) => is_in_base_folder(email.id));

                return found ?? traverse<Email>(all).first();

            case Location.OUT_OF_FOLDER_IN_FOLDER:
                Geary.Email? found = traverse<Email>(all)
                    .first_matching((email) => !is_in_base_folder(email.id));

                return found ?? traverse<Email>(all).first();

            default:
                assert_not_reached();
        }
    }

    private bool check_flag(Geary.NamedFlag flag, bool contains) {
        foreach (Geary.Email email in get_emails(Ordering.NONE)) {
            if (email.email_flags != null && email.email_flags.contains(flag) == contains)
                return true;
        }

        return false;
    }

    private bool has_flag(Geary.NamedFlag flag) {
        return check_flag(flag, true);
    }

    private bool is_missing_flag(Geary.NamedFlag flag) {
        return check_flag(flag, false);
    }

}
