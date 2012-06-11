/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.Transaction {
    private static NonblockingMutex? transaction_lock = null;
    private static int next_id = 0;
    private static string? held_by = null;
    
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
            // this may be the result of a programming error, but it can also be due to an exception
            // being thrown (particularly IOError.CANCELLED) when attempting an operation.
            if (is_commit_required)
                message("[%s] destroyed without committing or rolling back changes", to_string());
            
            resolve(false, null);
        }
    }
    
    public async void begin_async(Cancellable? cancellable = null) throws Error {
        assert(!is_locked);
        
        Logging.debug(Logging.Flag.TRANSACTIONS, "[%s] claiming lock held by %s", to_string(),
            !String.is_empty(held_by) ? held_by : "(no one)");
        claim_stub = yield transaction_lock.claim_async(cancellable);
        held_by = name;
        Logging.debug(Logging.Flag.TRANSACTIONS, "[%s] lock claimed", to_string());
    }
    
    private void resolve(bool commit, Cancellable? cancellable) throws Error {
        if (!is_locked) {
            warning("[%s] attempting to resolve an unlocked transaction", to_string());
            
            return;
        }
        
        if (commit)
            is_commit_required = false;
        
        Logging.debug(Logging.Flag.TRANSACTIONS, "[%s] releasing lock held by %s", to_string(),
            !String.is_empty(held_by) ? held_by : "(no one)");
        transaction_lock.release(ref claim_stub);
        held_by = null;
        Logging.debug(Logging.Flag.TRANSACTIONS, "[%s] released lock", to_string());
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
        Logging.debug(Logging.Flag.TRANSACTIONS, "[%s] commit required", to_string());
        
        is_commit_required = true;
    }
    
    public string to_string() {
        return "%d %s (%s%s)".printf(id, name, is_locked ? "locked" : "unlocked",
            is_commit_required ? ", commit required" : "");
    }
}

