/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public abstract class Geary.Sqlite.Table {
    internal weak Geary.Sqlite.Database gdb;
    internal SQLHeavy.Table table;
    
    internal Table(Geary.Sqlite.Database gdb, SQLHeavy.Table table) {
        this.gdb = gdb;
        this.table = table;
    }
    
    public string get_field_name(int col) throws SQLHeavy.Error {
        return table.field_name(col);
    }
    
    protected inline static int bool_to_int(bool b) {
        return b ? 1 : 0;
    }
    
    protected inline static bool int_to_bool(int i) {
        return !(i == 0);
    }
    
    protected async Transaction obtain_lock_async(Transaction? supplied_lock, string single_use_name,
        Cancellable? cancellable) throws Error {
        // if the user supplied the lock for multiple operations, use that
        if (supplied_lock != null) {
            if (!supplied_lock.is_locked)
                yield supplied_lock.begin_async(cancellable);
            
            return supplied_lock;
        }
        
        // create a single-use lock for the transaction
        return yield begin_transaction_async(single_use_name, cancellable);
    }
    
    // Technically this only needs to be called for locks that have a required commit.
    protected async void release_lock_async(Transaction? supplied_lock, Transaction actual_lock,
        Cancellable? cancellable) throws Error {
        // if user supplied a lock, don't touch it
        if (supplied_lock != null)
            return;
        
        // only commit if required (and the lock was single-use)
        if (actual_lock.is_commit_required)
            yield actual_lock.commit_async(cancellable);
    }
    
    protected async Transaction begin_transaction_async(string name, Cancellable? cancellable)
        throws Error {
        return yield gdb.begin_transaction_async(name, cancellable);
    }
    
    public string to_string() {
        return table.name;
    }
}

