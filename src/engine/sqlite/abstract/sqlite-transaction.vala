/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Transaction {
    private static NonblockingMutex? transaction_lock = null;
    private static int next_id = 0;
    
    public bool is_locked { get {
        return claim_stub != NonblockingMutex.INVALID_TOKEN;
    } }
    
    public bool is_commit_required { get; private set; default = false; }
    
    private SQLHeavy.Database db;
    private string name;
    private int id;
    private int claim_stub = NonblockingMutex.INVALID_TOKEN;
    
    internal Transaction(SQLHeavy.Database db, string name) throws Error {
        if (transaction_lock == null)
            transaction_lock = new NonblockingMutex();
        
        this.db = db;
        this.name = name;
        id = next_id++;
    }
    
    ~Transaction() {
        if (is_locked) {
            if (is_commit_required)
                warning("[%s] destroyed without committing or rolling back changes", to_string());
            
            resolve(false, null);
        }
    }
    
    public async void begin_async(Cancellable? cancellable = null) throws Error {
        assert(!is_locked);
#if TRACE_TRANSACTIONS
        debug("[%s] claiming lock", to_string());
#endif
        claim_stub = yield transaction_lock.claim_async(cancellable);
#if TRACE_TRANSACTIONS
        debug("[%s] lock claimed", to_string());
#endif
    }
    
    private void resolve(bool commit, Cancellable? cancellable) throws Error {
        if (!is_locked) {
            warning("[%s] attempting to resolve an unlocked transaction", to_string());
            
            return;
        }
        
        if (commit)
            is_commit_required = false;
        
#if TRACE_TRANSACTIONS
        debug("[%s] releasing lock", to_string());
#endif
        transaction_lock.release(ref claim_stub);
#if TRACE_TRANSACTIONS
        debug("[%s] released lock", to_string());
#endif
    }
    
    public SQLHeavy.Query prepare(string sql) throws Error {
        return db.prepare(sql);
    }
    
    public async void commit_async(Cancellable? cancellable) throws Error {
        resolve(true, cancellable);
    }
    
    public async void commit_if_required_async(Cancellable? cancellable) throws Error {
        if (is_commit_required)
            resolve(true, cancellable);
    }
    
    public async void rollback_async(Cancellable? cancellable) throws Error {
        resolve(false, cancellable);
    }
    
    public void set_commit_required() {
#if TRACE_TRANSACTIONS
        debug("[%s] commit required", to_string());
#endif
        is_commit_required = true;
    }
    
    public string to_string() {
        return "%d %s (%s%s)".printf(id, name, is_locked ? "locked" : "unlocked",
            is_commit_required ? ", commit required" : "");
    }
}

