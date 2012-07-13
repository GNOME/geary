/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Context allows for an inspector or utility function to determine at runtime what Geary.Db
 * objects are available to it.  Primarily designed for logging, but could be used in other
 * circumstances.
 *
 * Geary.Db's major classes (Database, Connection, Statement, and Result) inherit from Context.
 */

public abstract class Geary.Db.Context : Object {
    public virtual Database? get_database() {
        return get_connection() != null ? get_connection().database : null;
    }
    
    public virtual Connection? get_connection() {
        return get_statement() != null ? get_statement().connection : null;
    }
    
    public virtual Statement? get_statement() {
        return get_result() != null ? get_result().statement : null;
    }
    
    public virtual Result? get_result() {
        return null;
    }
    
    protected inline int throw_on_error(string? method, int result, string? raw = null) throws DatabaseError {
        return Db.throw_on_error(this, method, result, raw);
    }
    
    [PrintFormat]
    protected void log(string fmt, ...) {
        if (!Logging.are_all_flags_set(Logging.Flag.SQL))
            return;
        
        Connection? cx = get_connection();
        Statement? stmt = get_statement();
        
        if (stmt != null) {
            Logging.debug(Logging.Flag.SQL, "%s %s\n\t<%s>".printf(
                (cx != null) ? cx.to_string() : "[no cx]",
                fmt.vprintf(va_list()),
                (stmt != null) ? "%.100s".printf(stmt.sql) : "no sql"));
        } else {
            Logging.debug(Logging.Flag.SQL, "%s %s".printf(
                (cx != null) ? cx.to_string() : "[no cx]",
                fmt.vprintf(va_list())));
        }
    }
}

