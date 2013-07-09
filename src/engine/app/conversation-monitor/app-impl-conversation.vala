/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.App.ImplConversation : Geary.Conversation {
    private static int next_convnum = 0;
    
    public Gee.HashMultiSet<RFC822.MessageID> message_ids = new Gee.HashMultiSet<RFC822.MessageID>();
    
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
    
    public ImplConversation(Geary.App.ConversationMonitor owner) {
        convnum = next_convnum++;
        this.owner = owner;
        lowest_id = null;
        owner.email_flags_changed.connect(on_email_flags_changed);
    }
    
    ~ImplConversation() {
        clear_owner();
    }
    
    public void clear_owner() {
        if (owner != null)
            owner.email_flags_changed.disconnect(on_email_flags_changed);
        
        owner = null;
    }
    
    public override int get_count(bool folder_email_ids_only = false) {
        if (!folder_email_ids_only)
            return emails.size;
        
        int folder_count = 0;
        foreach (Geary.EmailIdentifier id in emails.keys) {
            if (id.folder_path != null)
                ++folder_count;
        }
        return folder_count;
    }
    
    public override Gee.List<Geary.Email> get_emails(Conversation.Ordering ordering) {
        switch (ordering) {
            case Conversation.Ordering.DATE_ASCENDING:
                return Collection.to_array_list<Email>(date_ascending);
            
            case Conversation.Ordering.DATE_DESCENDING:
                return Collection.to_array_list<Email>(date_descending);
            
            case Conversation.Ordering.NONE:
            default:
                return Collection.to_array_list<Email>(emails.values);
        }
    }
    
    public override Gee.Collection<RFC822.MessageID> get_message_ids() {
        // Turn into a HashSet first, so we don't return duplicates.
        Gee.HashSet<RFC822.MessageID> ids = new Gee.HashSet<RFC822.MessageID>();
        ids.add_all(message_ids);
        return ids;
    }
    
    public override Geary.Email? get_email_by_id(EmailIdentifier id) {
        return emails.get(id);
    }
    
    public override Gee.Collection<Geary.EmailIdentifier> get_email_ids(
        bool folder_email_ids_only = false) {
        if (!folder_email_ids_only)
            return emails.keys;
        
        Gee.ArrayList<Geary.EmailIdentifier> folder_ids = new Gee.ArrayList<Geary.EmailIdentifier>();
        foreach (Geary.EmailIdentifier id in emails.keys) {
            if (id.folder_path != null)
                folder_ids.add(id);
        }
        return folder_ids;
    }
    
    public override Geary.EmailIdentifier? get_lowest_email_id() {
        return lowest_id;
    }
    
    /**
     * Add the email to the conversation.  If an email with a matching id
     * already exists, the old email may be removed and the new one inserted in
     * its place (this will happen if the new email is "in-folder" but the old
     * one was "out-of-folder", for example).  Return false if the new email is
     * ignored entirely, or true if it's either new or replaced an older one.
     */
    public bool add(Email email) {
        Email? existing = emails.get(email.id);
        if (existing != null) {
            // We "promote" out-of-folder emails to in-folder emails so we
            // always have the most useful version.
            // FIXME: this assumes that all data about the existing and new
            // email are identical.  That might not be the case.
            if (existing.id.folder_path == null && email.id.folder_path != null)
                remove(existing);
            else
                return false;
        }
        
        emails.set(email.id, email);
        date_ascending.add(email);
        date_descending.add(email);
        
        Gee.Set<RFC822.MessageID>? ancestors = email.get_ancestors();
        if (ancestors != null)
            message_ids.add_all(ancestors);
        
        check_lowest_id(email.id);
        notify_appended(email);
        
        return true;
    }
    
    // Returns the removed Message-IDs
    public Gee.Set<RFC822.MessageID>? remove(Email email) {
        emails.unset(email.id);
        date_ascending.remove(email);
        date_descending.remove(email);
        
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
        
        notify_trimmed(email);
        
        return (removed_message_ids.size > 0) ? removed_message_ids : null;
    }
    
    private void check_lowest_id(EmailIdentifier id) {
        if (id.folder_path != null && (lowest_id == null || id.compare_to(lowest_id) < 0))
            lowest_id = id;
    }
    
    public string to_string() {
        return "[#%d] (%d emails)".printf(convnum, emails.size);
    }
    
    private void on_email_flags_changed(Geary.Conversation conversation, Geary.Email email) {
        if (conversation == this)
            notify_email_flags_changed(email);
    }
}
