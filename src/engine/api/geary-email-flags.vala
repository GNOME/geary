/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.EmailFlags : Geary.Equalable {
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
    
    public EmailFlags() {
    }
    
    public bool contains(EmailFlag flag) {
        return list.contains(flag);
    }
    
    public Gee.Set<EmailFlag> get_all() {
        return list.read_only_view;
    }
    
    public virtual void add(EmailFlag flag) {
        list.add(flag);
    }
    
    public virtual bool remove(EmailFlag flag) {
        return list.remove(flag);
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

