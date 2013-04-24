/* Copyright 2012-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Singleton is a simple way of creating a one-item read-only collection.
 */
private class Geary.Singleton<G> : Gee.AbstractCollection<G> {
    private class IteratorImpl<G> : BaseObject, Gee.Iterator<G> {
        private G item;
        private bool done = false;
        
        public IteratorImpl(G item) {
            this.item = item;
        }
        
        public bool first() {
            done = false;
            
            return true;
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
            message("Geary.Singleton is read-only");
        }
    }
    
    public G item { get; private set; }
    public override int size { get { return 1; } }
    
    private EqualFunc equal_func;
    
    public Singleton(G item, EqualFunc? equal_func = null) {
        this.item = item;
        
        if (equal_func != null)
            this.equal_func = equal_func;
        else if (typeof(G).is_a(typeof(Geary.Equalable)))
            this.equal_func = Geary.Equalable.equal_func;
        else
            this.equal_func = Gee.Functions.get_equal_func_for(typeof(G));
    }
    
    public override bool add(G element) {
        return false;
    }
    
    public override void clear() {
        message("Geary.Singleton is read-only");
    }
    
    public override bool contains(G element) {
        return equal_func(item, element);
    }
    
    public override Gee.Iterator<G> iterator() {
        return new IteratorImpl<G>(item);
    }
    
    public override bool remove(G element) {
        message("Geary.Singleton is read-only");
        
        return false;
    }
}

