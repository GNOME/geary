/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.Db.TransactionOutcome {
    ROLLBACK = 0,
    COMMIT = 1,

    // coarse synonyms
    SUCCESS = COMMIT,
    FAILURE = ROLLBACK,
    DONE = COMMIT;

    public unowned string sql() {
        switch (this) {
            case COMMIT:
                return "COMMIT TRANSACTION";

            case ROLLBACK:
            default:
                return "ROLLBACK TRANSACTION";
        }
    }

    public string to_string() {
        switch (this) {
            case ROLLBACK:
                return "rollback";

            case COMMIT:
                return "commit";

            default:
                return "(unknown: %d)".printf(this);
        }
    }
}

