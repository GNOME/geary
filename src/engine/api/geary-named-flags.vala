/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A signalled collection of NamedFlags.  Currently Geary uses these flags for enabling/disabling
 * options with email or contacts.
 */

public class Geary.NamedFlags : BaseObject, Gee.Hashable<Geary.NamedFlags> {
    protected Gee.Set<NamedFlag> list = new Gee.HashSet<NamedFlag>();
    
    public virtual signal void added(Gee.Collection<NamedFlag> flags) {
    }
    
    public virtual signal void removed(Gee.Collection<NamedFlag> flags) {
    }
    
    public NamedFlags() {
    }
    
    protected virtual void notify_added(Gee.Collection<NamedFlag> flags) {
        added(flags);
    }
    
    protected virtual void notify_removed(Gee.Collection<NamedFlag> flags) {
        removed(flags);
    }
    
    public bool contains(NamedFlag flag) {
        return list.contains(flag);
    }
    
    public Gee.Set<NamedFlag> get_all() {
        return list.read_only_view;
    }
    
    public virtual void add(NamedFlag flag) {
        if (!list.contains(flag)) {
            list.add(flag);
            notify_added(new Collection.SingleItem<NamedFlag>(flag));
        }
    }
    
    public virtual void add_all(NamedFlags flags) {
        Gee.ArrayList<NamedFlag> added = new Gee.ArrayList<NamedFlag>();
        foreach (NamedFlag flag in flags.get_all()) {
            if (!list.contains(flag))
                added.add(flag);
        }
        
        list.add_all(added);
        notify_added(added);
    }
    
    public virtual bool remove(NamedFlag flag) {
        bool removed = list.remove(flag);
        if (removed)
            notify_removed(new Collection.SingleItem<NamedFlag>(flag));
        
        return removed;
    }
    
    public virtual bool remove_all(NamedFlags flags) {
        Gee.ArrayList<NamedFlag> removed = new Gee.ArrayList<NamedFlag>();
        foreach (NamedFlag flag in flags.get_all()) {
            if (list.contains(flag))
                removed.add(flag);
        }
        
        list.remove_all(removed);
        notify_removed(removed);
        
        return removed.size > 0;
    }
    
    public bool equal_to(Geary.NamedFlags other) {
        if (this == other)
            return true;
        
        if (list.size != other.list.size)
            return false;
        
        foreach (NamedFlag flag in list) {
            if (!other.contains(flag))
                return false;
        }
        
        return true;
    }
    
    public uint hash() {
        return Geary.String.stri_hash(to_string());
    }
    
    public string to_string() {
        string ret = "[";
        foreach (NamedFlag flag in list) {
            ret += flag.to_string() + " ";
        }
        
        return ret + "]";
    }
}

