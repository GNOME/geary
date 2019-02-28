/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.Db.TransactionType {
    DEFERRED,
    IMMEDIATE,
    EXCLUSIVE,

    // coarse synonyms
    RO = DEFERRED,
    RW = IMMEDIATE,
    WR = EXCLUSIVE,
    WO = EXCLUSIVE;

    public unowned string sql() {
        switch (this) {
            case IMMEDIATE:
                return "BEGIN IMMEDIATE";

            case EXCLUSIVE:
                return "BEGIN EXCLUSIVE";

            case DEFERRED:
            default:
                return "BEGIN DEFERRED";
        }
    }

    public string to_string() {
        switch (this) {
            case DEFERRED:
                return "DEFERRED";

            case IMMEDIATE:
                return "IMMEDIATE";

            case EXCLUSIVE:
                return "EXCLUSIVE";

            default:
                return "(unknown: %d)".printf(this);
        }
    }
}

