/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * SingleItem is a simple way of creating a one-item read-only Gee.Collection.
 */
public class Geary.Collection.SingleItem<G> : Gee.AbstractCollection<G> {
    private class IteratorImpl<G> : BaseObject, Gee.Traversable<G>, Gee.Iterator<G> {
        public bool read_only { get { return true; } }
        public bool valid { get { return !done; } }
        
        private G item;
        private bool done = false;
        
        public IteratorImpl(G item) {
            this.item = item;
        }
        
        public new G? get() {
            return item;
        }
        
        public bool has_next() {
            return !done;
        }
        
        public bool next() {
            if (done)
                return false;
            
            done = true;
            
            return true;
        }
        
        public void remove() {
            warn_readonly();
        }
        
        public new bool @foreach(Gee.ForallFunc<G> f) {
            return f(item);
       }
    }
    
    public override bool read_only { get { return true; } }
    public G item { get; private set; }
    public override int size { get { return 1; } }
    
    private Gee.EqualDataFunc equal_func;
    
    public SingleItem(G item, owned Gee.EqualDataFunc? equal_func = null) {
        this.item = item;
        
        if (equal_func != null)
            this.equal_func = (owned) equal_func;
        else {
            this.equal_func = Gee.Functions.get_equal_func_for(typeof(G));
        }
    }
    
    private static void warn_readonly() {
        message("Geary.Collection.SingleItem is read-only");
    }
    
    public override bool add(G element) {
        return false;
    }
    
    public override void clear() {
        warn_readonly();
    }
    
    public override bool contains(G element) {
        return equal_func(item, element);
    }
    
    public override Gee.Iterator<G> iterator() {
        return new IteratorImpl<G>(item);
    }
    
    public override bool remove(G element) {
        warn_readonly();
        
        return false;
    }
}

