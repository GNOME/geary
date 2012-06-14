/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

class DbTest : MainAsync {
    public const string DB_FILENAME="db-test.db";
    
    public DbTest(string[] args) {
        base (args);
    }
    
    protected async override int exec_async() throws Error {
        if (args.length < 2) {
            stderr.printf("usage: db-test <data-dir>\n");
            
            return 1;
        }
        
        Geary.Logging.log_to(stdout);
        
        File schema_dir =
            File.new_for_commandline_arg(args[0]).get_parent().get_child("src").get_child("db-test");
        File data_file = File.new_for_commandline_arg(args[1]).get_child(DB_FILENAME);
        
        debug("schema_dir=%s data_file=%s\n", schema_dir.get_path(), data_file.get_path());
        
        Geary.Db.VersionedDatabase db = new Geary.Db.VersionedDatabase(data_file, schema_dir);
        
        debug("Opening %s...", db.db_file.get_path());
        db.open(Geary.Db.DatabaseFlags.CREATE_DIRECTORY | Geary.Db.DatabaseFlags.CREATE_FILE,
            on_prepare_connection);
        
        Geary.Db.Connection cx = db.open_connection();
        
        debug("Sync select...");
        Geary.Db.TransactionOutcome outcome = cx.exec_transaction(Geary.Db.TransactionType.RO, (cx) => {
            Geary.Db.Result result = cx.prepare("SELECT str FROM AnotherTable").exec();
            
            int ctr = 0;
            while (!result.finished) {
                stdout.printf("[%d] %s\n", ctr++, result.string_at(0));
                result.next();
            }
            
            return Geary.Db.TransactionOutcome.COMMIT;
        });
        debug("Sync select: %s", outcome.to_string());
        
        outcome = cx.exec_transaction(Geary.Db.TransactionType.WO, (cx) => {
            for (int ctr = 0; ctr < 10; ctr++)
                cx.prepare("INSERT INTO AnotherTable (str) VALUES (?)").bind_string(0, ctr.to_string()).exec();
            
            return Geary.Db.TransactionOutcome.COMMIT;
        });
        
        debug("Async select");
        outcome = yield db.exec_transaction_async(Geary.Db.TransactionType.RO, (cx) => {
            Geary.Db.Result result = cx.prepare("SELECT str FROM AnotherTable").exec();
            
            int ctr = 0;
            while (!result.finished) {
                stdout.printf("[%d]a %s\n", ctr++, result.string_at(0));
                result.next();
            }
            
            return Geary.Db.TransactionOutcome.COMMIT;
        }, null);
        debug("Async select finished");
        
        debug("Multi async write");
        db.exec("DELETE FROM MultiTable");
        db.exec_transaction_async.begin(Geary.Db.TransactionType.RW, (cx) => {
            return do_insert_async(cx, 0);
        }, null, on_async_completed);
        db.exec_transaction_async.begin(Geary.Db.TransactionType.RW, (cx) => {
            return do_insert_async(cx, 100);
        }, null, on_async_completed);
        db.exec_transaction_async.begin(Geary.Db.TransactionType.RW, (cx) => {
            return do_insert_async(cx, 1000);
        }, null, on_async_completed);
        
        yield;
        
        debug("Exiting...");
        
        return 0;
    }
    
    private Geary.Db.TransactionOutcome do_insert_async(Geary.Db.Connection cx, int start) throws Error {
        for (int ctr = start; ctr < (start + 10); ctr++) {
            cx.prepare("INSERT INTO MultiTable (str) VALUES (?)").bind_int(0, ctr).exec();
            
            debug("%d sleeping...", start);
            Thread.usleep(10);
            debug("%d woke up", start);
        }
        
        return Geary.Db.TransactionOutcome.COMMIT;
    }
    
    private void on_async_completed(Object? source, AsyncResult result) {
        Geary.Db.Database db = (Geary.Db.Database) source;
        
        try {
            stdout.printf("Completed: %s\n", db.exec_transaction_async.end(result).to_string());
        } catch (Error err) {
            stdout.printf("Completed w/ err: %s\n", err.message);
        }
    }
    
    private void on_prepare_connection(Geary.Db.Connection cx) throws Error {
        cx.set_busy_timeout_msec(1000);
        cx.set_synchronous(Geary.Db.SynchronousMode.OFF);
    }
}

int main(string[] args) {
    return new DbTest(args).exec();
}

