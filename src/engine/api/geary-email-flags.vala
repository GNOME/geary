/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.EmailFlags : BaseObject, Geary.Equalable {
    private static EmailFlag? _unread = null;
    public static EmailFlag UNREAD { get {
        if (_unread == null)
            _unread = new EmailFlag("UNREAD");
        
        return _unread;
    } }

    private static EmailFlag? _flagged = null;
    public static EmailFlag FLAGGED { get {
        if (_flagged == null)
            _flagged = new EmailFlag("FLAGGED");

        return _flagged;
    } }

    private Gee.Set<EmailFlag> list = new Gee.HashSet<EmailFlag>(Hashable.hash_func, Equalable.equal_func);
    
    public virtual signal void added(Gee.Collection<EmailFlag> flags) {
    }
    
    public virtual signal void removed(Gee.Collection<EmailFlag> flags) {
    }
    
    public EmailFlags() {
    }
    
    protected virtual void notify_added(Gee.Collection<EmailFlag> flags) {
        added(flags);
    }
    
    protected virtual void notify_removed(Gee.Collection<EmailFlag> flags) {
        removed(flags);
    }
    
    public bool contains(EmailFlag flag) {
        return list.contains(flag);
    }
    
    public Gee.Set<EmailFlag> get_all() {
        return list.read_only_view;
    }
    
    public virtual void add(EmailFlag flag) {
        if (!list.contains(flag)) {
            list.add(flag);
            notify_added(new Singleton<EmailFlag>(flag));
        }
    }
    
    public virtual void add_all(EmailFlags flags) {
        Gee.ArrayList<EmailFlag> added = new Gee.ArrayList<EmailFlag>();
        foreach (EmailFlag flag in flags.get_all()) {
            if (!list.contains(flag))
                added.add(flag);
        }
        
        list.add_all(added);
        notify_added(added);
    }
    
    public virtual bool remove(EmailFlag flag) {
        bool removed = list.remove(flag);
        if (removed)
            notify_removed(new Singleton<EmailFlag>(flag));
        
        return removed;
    }
    
    public virtual bool remove_all(EmailFlags flags) {
        Gee.ArrayList<EmailFlag> removed = new Gee.ArrayList<EmailFlag>();
        foreach (EmailFlag flag in flags.get_all()) {
            if (list.contains(flag))
                removed.add(flag);
        }
        
        list.remove_all(removed);
        notify_removed(removed);
        
        return removed.size > 0;
    }
    
    // Convenience method to check if the unread flag is set.
    public inline bool is_unread() {
        return contains(UNREAD);
    }

    public inline bool is_flagged() {
        return contains(FLAGGED);
    }

    public bool equals(Equalable o) {
        Geary.EmailFlags? other = o as Geary.EmailFlags;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        if (list.size != other.list.size)
            return false;
        
        foreach (EmailFlag flag in list) {
            if (!other.contains(flag))
                return false;
        }
        
        return true;
    }
    
    public string to_string() {
        string ret = "[";
        foreach (EmailFlag flag in list) {
            ret += flag.to_string() + " ";
        }
        
        return ret + "]";
    }
}

