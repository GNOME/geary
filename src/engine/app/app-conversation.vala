/* Copyright 2011-2015 Yorba Foundation
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
     * Specify the location of the {@link Email} in relation to the {@link Folder} being monitored
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
    
    private int convnum;
    private weak Geary.App.ConversationMonitor? owner;
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
    
    // by storing all paths for each EmailIdentifier, can lookup without blocking
    private Gee.HashMultiMap<Geary.EmailIdentifier, Geary.FolderPath> path_map = new Gee.HashMultiMap<
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
        
        owner.email_flags_changed.connect(on_email_flags_changed);
    }
    
    ~Conversation() {
        clear_owner();
    }
    
    internal void clear_owner() {
        if (owner == null)
            return;
        
        owner.email_flags_changed.disconnect(on_email_flags_changed);
        
        owner = null;
    }
    
    /**
     * Returns the number of emails in the conversation.
     */
    public int get_count() {
        return emails.size;
    }
    
    /**
     * Returns true if any {@link Email}s in the {@link Conversation} are known to be in the
     * specified {@link FolderPath}.
     */
    public bool any_in_folder_path(Geary.FolderPath path) {
        foreach (EmailIdentifier email_id in path_map.get_keys()) {
            if (path_map.get(email_id).contains(path))
                return true;
        }
        
        return false;
    }
    
    /**
     * Returns all the email in the conversation sorted and filtered according to the specifiers.
     *
     * {@link Location.IN_FOLDER} and {@link Location.OUT_OF_FOLDER} are the
     * only preferences honored; the others ({@link Location.IN_FOLDER_OUT_OF_FOLDER},
     * {@link Location.IN_FOLDER_OUT_OF_FOLDER}, and {@link Location.ANYWHERE}
     * are all treated as ANYWHERE.
     */
    public Gee.Collection<Geary.Email> get_emails(Ordering ordering, Location location = Location.ANYWHERE) {
        Gee.Collection<Geary.Email> email;
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
        
        switch (location) {
            case Location.IN_FOLDER:
                email = traverse<Email>(email)
                    .filter((e) => !is_in_current_folder(e.id))
                    .to_array_list();
            break;
            
            case Location.OUT_OF_FOLDER:
                email = traverse<Email>(email)
                    .filter((e) => is_in_current_folder(e.id))
                    .to_array_list();
            break;
            
            case Location.IN_FOLDER_OUT_OF_FOLDER:
            case Location.OUT_OF_FOLDER_IN_FOLDER:
            case Location.ANYWHERE:
                // make a modifiable copy
                email = traverse<Email>(email).to_array_list();
            break;
            
            default:
                assert_not_reached();
        }
        
        return email;
    }
    
    public bool is_in_current_folder(Geary.EmailIdentifier id) {
        Gee.Collection<Geary.FolderPath>? paths = path_map.get(id);
        
        return (paths != null && paths.contains(owner.folder.path));
    }
    
    /**
     * Returns the email associated with the EmailIdentifier, if present in this conversation.
     */
    public Geary.Email? get_email_by_id(EmailIdentifier id) {
        return emails.get(id);
    }
    
    /**
     * Returns the known {@link FolderPath}s for the {@link EmailIdentifier}.
     */
    public Gee.Collection<Geary.FolderPath>? get_known_paths_for_id(Geary.EmailIdentifier id) {
        return path_map.get(id);
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
     *
     * Paths are always added, whether or not the email was already present.
     */
    internal bool add(Email email, Gee.Collection<Geary.FolderPath> known_paths) {
        foreach (Geary.FolderPath path in known_paths)
            path_map.set(email.id, path);
        
        if (emails.has_key(email.id))
            return false;
        
        emails.set(email.id, email);
        sent_date_ascending.add(email);
        sent_date_descending.add(email);
        recv_date_ascending.add(email);
        recv_date_descending.add(email);
        
        appended(email);
        
        return true;
    }
    
    /**
     * Removes the paths from the email's known paths in the conversation.
     *
     * Returns true if the email is fully removed from the conversation.
     */
    internal bool remove(Email email, Geary.FolderPath path) {
        path_map.remove(email.id, path);
        if (path_map.get(email.id).size != 0)
            return false;
        
        emails.unset(email.id);
        sent_date_ascending.remove(email);
        sent_date_descending.remove(email);
        recv_date_ascending.remove(email);
        recv_date_descending.remove(email);
        
        trimmed(email);
        
        return true;
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
     * Returns the earliest (first sent) email in the Conversation.
     */
    public Geary.Email? get_earliest_sent_email(Location location) {
        return get_single_email(Ordering.SENT_DATE_ASCENDING, location);
    }
    
    /**
     * Returns the latest (most recently sent) email in the Conversation.
     */
    public Geary.Email? get_latest_sent_email(Location location) {
        return get_single_email(Ordering.SENT_DATE_DESCENDING, location);
    }
    
    /**
     * Returns the earliest (first received) email in the Conversation.
     */
    public Geary.Email? get_earliest_recv_email(Location location) {
        return get_single_email(Ordering.RECV_DATE_ASCENDING, location);
    }
    
    /**
     * Returns the latest (most recently received) email in the Conversation.
     */
    public Geary.Email? get_latest_recv_email(Location location) {
        return get_single_email(Ordering.RECV_DATE_DESCENDING, location);
    }
    
    private Geary.Email? get_single_email(Ordering ordering, Location location) {
        // note that the location-ordering preferences are treated as ANYWHERE by get_emails()
        Gee.Collection<Geary.Email> all = get_emails(ordering, location);
        if (all.size == 0)
            return null;
        
        // Because IN_FOLDER_OUT_OF_FOLDER and OUT_OF_FOLDER_IN_FOLDER are treated as ANYWHERE,
        // have to do our own filtering
        switch (location) {
            case Location.IN_FOLDER:
            case Location.OUT_OF_FOLDER:
            case Location.ANYWHERE:
                return traverse<Email>(all).first();
            
            case Location.IN_FOLDER_OUT_OF_FOLDER:
                Geary.Email? found = traverse<Email>(all)
                    .first_matching((email) => is_in_current_folder(email.id));
                
                return found ?? traverse<Email>(all).first();
            
            case Location.OUT_OF_FOLDER_IN_FOLDER:
                Geary.Email? found = traverse<Email>(all)
                    .first_matching((email) => !is_in_current_folder(email.id));
                
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
    
    private void on_email_flags_changed(Conversation conversation, Geary.Email email) {
        if (conversation == this)
            email_flags_changed(email);
    }
    
    public string to_string() {
        return "[#%d] (%d emails)".printf(convnum, emails.size);
    }
}
