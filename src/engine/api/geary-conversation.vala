/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Conversation : Object {
    protected Conversation() {
    }
    
    /**
     * Returns the number of emails in the conversation.
     */
    public abstract int get_count();
    
    /**
     * Returns all the email in the conversation, unsorted.
     */
    public abstract Gee.Collection<Geary.Email> get_email();
    
    /**
     * Returns all emails in the conversation sorted by the supplied CompareFunc.
     */
    public Gee.SortedSet<Geary.Email> get_email_sorted(CompareFunc<Geary.Email> compare_func) {
        Gee.TreeSet<Geary.Email> sorted = new Gee.TreeSet<Geary.Email>(compare_func);
        sorted.add_all(get_email());
        
        return sorted;
    }
    
    /**
     * Returns true if *any* message in the conversation is unread.
     */
    public virtual bool is_unread() {
        foreach (Geary.Email email in get_email()) {
            if (email.is_unread().to_boolean(false))
                return true;
        }

        return false;
    }

    /**
     * Returns true if *any* message in the conversation is flagged.
     */
    public virtual bool is_flagged() {
        foreach (Geary.Email email in get_email()) {
            if (email.is_flagged().to_boolean(false))
                return true;
        }

        return false;
    }
}

