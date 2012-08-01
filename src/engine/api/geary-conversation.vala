/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Conversation : Object {
    public enum Ordering {
        NONE,
        DATE_ASCENDING,
        DATE_DESCENDING,
        ID_ASCENDING,
        ID_DESCENDING
    }
    
    protected Conversation() {
    }
    
    /**
     * Returns the number of emails in the conversation.
     */
    public abstract int get_count();
    
    /**
     * Returns all the email in the conversation sorted according to the specifier.
     */
    public abstract Gee.List<Geary.Email> get_emails(Ordering ordering);
    
    /**
     * Returns the email associated with the EmailIdentifier, if present in this conversation.
     */
    public abstract Geary.Email? get_email_by_id(Geary.EmailIdentifier id);
    
    /**
     * Returns all EmailIdentifiers in the conversation, unsorted.
     */
    public abstract Gee.Collection<Geary.EmailIdentifier> get_email_ids();
    
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
     * Returns the email to use for a preview in a conversation.
     */
    public Geary.Email? get_latest_email() {
        Gee.List<Geary.Email> pool = get_emails(Geary.Conversation.Ordering.DATE_ASCENDING);
        return pool.size == 0 ? null : pool.last();
    }
    
    private bool check_flag(Geary.EmailFlag flag, bool contains) {
        foreach (Geary.Email email in get_emails(Ordering.NONE)) {
            if (email.email_flags != null && email.email_flags.contains(flag) == contains)
                return true;
        }
        
        return false;
    }

    private bool has_flag(Geary.EmailFlag flag) {
        return check_flag(flag, true);
    }

    private bool is_missing_flag(Geary.EmailFlag flag) {
        return check_flag(flag, false);
    }
}

