/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.App.Conversation : BaseObject {
    public enum Ordering {
        NONE,
        DATE_ASCENDING,
        DATE_DESCENDING,
    }
    
    private static int next_convnum = 0;
    
    private Gee.HashMultiSet<RFC822.MessageID> message_ids = new Gee.HashMultiSet<RFC822.MessageID>();
    
    private int convnum;
    private weak Geary.App.ConversationMonitor? owner;
    private Gee.HashMap<EmailIdentifier, Email> emails = new Gee.HashMap<EmailIdentifier, Email>();
    private Geary.EmailIdentifier? lowest_id;
    
    // this isn't ideal but the cost of adding an email to multiple sorted sets once versus
    // the number of times they're accessed makes it worth it
    private Gee.SortedSet<Email> date_ascending = new Collection.FixedTreeSet<Email>(
        Geary.Email.compare_date_ascending);
    private Gee.SortedSet<Email> date_descending = new Collection.FixedTreeSet<Email>(
        Geary.Email.compare_date_descending);
    
    // by storing all paths for each EmailIdentifier, can lookup without blocking
    Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath> path_map = new Gee.HashMultiMap<
        Geary.EmailIdentifier, Geary.FolderPath>();
    
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
    
    public Conversation(Geary.App.ConversationMonitor owner) {
        convnum = next_convnum++;
        this.owner = owner;
        lowest_id = null;
        
        owner.email_flags_changed.connect(on_email_flags_changed);
        owner.folder.account.email_discovered.connect(on_email_discovered);
        owner.folder.account.email_removed.connect(on_email_removed);
    }
    
    ~Conversation() {
        clear_owner();
    }
    
    internal void clear_owner() {
        if (owner != null) {
            owner.email_flags_changed.disconnect(on_email_flags_changed);
            owner.folder.account.email_discovered.disconnect(on_email_discovered);
            owner.folder.account.email_removed.disconnect(on_email_removed);
        }
        
        owner = null;
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
    public async int get_count_in_folder_async(Geary.Account account, Geary.FolderPath path,
        Cancellable? cancellable) throws Error {
        Gee.MultiMap<Geary.EmailIdentifier, Geary.FolderPath>? folder_map
            = yield account.get_containing_folders_async(emails.keys, cancellable);
        
        int count = 0;
        if (folder_map != null) {
            foreach (Geary.EmailIdentifier id in folder_map.get_keys()) {
                if (path in folder_map.get(id))
                    ++count;
            }
        }
        
        return count;
    }
    
    /**
     * Returns all the email in the conversation sorted according to the specifier.
     */
    public Gee.List<Geary.Email> get_emails(Ordering ordering, bool only_in_current_folder = false) {
        Gee.List<Geary.Email> list;
        switch (ordering) {
            case Ordering.DATE_ASCENDING:
                list = Collection.to_array_list<Email>(date_ascending);
            break;
            
            case Ordering.DATE_DESCENDING:
                list = Collection.to_array_list<Email>(date_descending);
            break;
            
            case Ordering.NONE:
            default:
                list = Collection.to_array_list<Email>(emails.values);
            break;
        }
        
        if (!only_in_current_folder)
            return list;
        
        // remove emails not in current folder
        Gee.Iterator<Geary.Email> iter = list.iterator();
        while (iter.next()) {
            if (!is_in_current_folder(iter.get().id))
                iter.remove();
        }
        
        return list;
    }
    
    public bool is_in_current_folder(Geary.EmailIdentifier id) {
        Gee.Collection<Geary.FolderPath>? paths = path_map.get(id);
        
        return (paths != null && paths.contains(owner.folder.path));
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
     * Returns the email associated with the EmailIdentifier, if present in this conversation.
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
     * Add the email to the conversation if it wasn't already in there.  Return
     * whether it was added.
     *
     * known_paths should contain all the known FolderPaths this email is contained in.
     * Conversation will monitor Account for additions and removals as they occur.
     */
    internal bool add(Email email, Gee.Collection<Geary.FolderPath> known_paths) {
        if (emails.has_key(email.id))
            return false;
        
        emails.set(email.id, email);
        date_ascending.add(email);
        date_descending.add(email);
        
        Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null)
            message_ids.add_all(ancestors);
        
        foreach (Geary.FolderPath path in known_paths)
            path_map.set(email.id, path);
        
        check_lowest_id(email.id);
        
        appended(email);
        
        return true;
    }
    
    // Returns the removed Message-IDs
    internal Gee.Set<RFC822.MessageID>? remove(Email email) {
        emails.unset(email.id);
        date_ascending.remove(email);
        date_descending.remove(email);
        path_map.remove_all(email.id);
        
        Gee.Set<RFC822.MessageID> removed_message_ids = new Gee.HashSet<RFC822.MessageID>();
        
        Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null) {
            foreach (RFC822.MessageID ancestor_id in ancestors) {
                // if remove() changes set (i.e. it was present) but no longer present, that
                // means the ancestor_id was the last one and is formally removed
                if (message_ids.remove(ancestor_id) && !message_ids.contains(ancestor_id))
                    removed_message_ids.add(ancestor_id);
            }
        }
        
        lowest_id = null;
        foreach (Email e in emails.values)
            check_lowest_id(e.id);
        
        trimmed(email);
        
        return (removed_message_ids.size > 0) ? removed_message_ids : null;
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
     * Returns true if this Conversation's earliest (first sent) email is earlier than
     * the supplied Conversation's earliest email.  An empty Conversation is defined as being
     * earlier than a non-empty conversation.  Comparing two empty Conversations or two Conversations
     * with the same earliest date is undefined.
     */
    public bool is_earlier(Conversation other) {
        Email? this_earliest = get_earliest_email();
        Email? other_earliest = other.get_earliest_email();
        
        if (this_earliest == null)
            return true;
        
        // this_earliest != null
        if (other_earliest == null)
            return false;
        
        return this_earliest.date.value.compare(other_earliest.date.value) < 0;
    }
    
    /**
     * Returns true if this Conversation's latest (most recently sent) email is more recent than
     * the supplied Conversation's latest email.  An empty Conversation is defined as being
     * earlier than a non-empty conversation.  Comparing two empty Conversations or two
     * Conversations with the same latest date is undefined.
     */
    public bool is_later(Conversation other) {
        Email? this_latest = get_latest_email();
        Email? other_latest = other.get_latest_email();
        
        if (this_latest == null)
            return (other_latest != null);
        
        // this_latest != null
        if (other_latest == null)
            return true;
        
        return this_latest.date.value.compare(other_latest.date.value) > 0;
    }
    
    /**
     * Returns the earliest (first sent) email in the Conversation.
     */
    public Geary.Email? get_earliest_email(bool only_in_current_folder = false) {
        return get_single_email(Ordering.DATE_ASCENDING, only_in_current_folder);
    }
    
    /**
     * Returns the latest (most recently sent) email in the Conversation.
     */
    public Geary.Email? get_latest_email(bool only_in_current_folder = false) {
        return get_single_email(Ordering.DATE_DESCENDING, only_in_current_folder);
    }
    
    private Geary.Email? get_single_email(Ordering ordering, bool only_in_current_folder) {
        return Geary.Collection.get_first<Geary.Email>(get_emails(ordering, only_in_current_folder));
    }
    
    /**
     * Return the EmailIdentifier with the lowest value.  Ignore Geary.ImapDB.
     * EmailIdentifiers, because they aren't useful to order in this sense.
     */
    public Geary.EmailIdentifier? get_lowest_email_id() {
        return lowest_id;
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
    
    private void check_lowest_id(EmailIdentifier id) {
        if (lowest_id == null || id.natural_sort_comparator(lowest_id) < 0)
            lowest_id = id;
    }
    
    private void on_email_flags_changed(Conversation conversation, Geary.Email email) {
        if (conversation == this)
            email_flags_changed(email);
    }
    
    private void on_email_discovered(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        // only add to the internal map if a part of this Conversation
        foreach (Geary.EmailIdentifier id in ids) {
            if (emails.has_key(id))
                path_map.set(id, folder.path);
        }
    }
    
    private void on_email_removed(Geary.Folder folder, Gee.Collection<Geary.EmailIdentifier> ids) {
        // To be forgiving, simply remove id without checking if it's a part of this Conversation
        foreach (Geary.EmailIdentifier id in ids)
            path_map.remove(id, folder.path);
    }
    
    public string to_string() {
        return "[#%d] (%d emails)".printf(convnum, emails.size);
    }
}
