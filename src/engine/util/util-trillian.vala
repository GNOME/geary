/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A trillian is a three-state boolean, used when the value is potentially unknown.
 */

public enum Geary.Trillian {
    // DO NOT MODIFY unless you know what you're doing.  These values are persisted.
    UNKNOWN = -1,
    FALSE = 0,
    TRUE = 1;

    public bool to_boolean(bool if_unknown) {
        switch (this) {
            case UNKNOWN:
                return if_unknown;

            case FALSE:
                return false;

            case TRUE:
                return true;

            default:
                assert_not_reached();
        }
    }

    public inline static Trillian from_boolean(bool b) {
        return b ? TRUE : FALSE;
    }

    public inline int to_int() {
        return (int) this;
    }

    public static Trillian from_int(int i) {
        switch (i) {
            case 0:
                return FALSE;

            case 1:
                return TRUE;

            default:
                return UNKNOWN;
        }
    }

    public inline bool is_certain() {
        return this == TRUE;
    }

    public inline bool is_uncertain() {
        return this != TRUE;
    }

    public inline bool is_possible() {
        return this != FALSE;
    }

    public inline bool is_impossible() {
        return this == FALSE;
    }

    public string to_string() {
        switch (this) {
            case UNKNOWN:
                return "unknown";

            case FALSE:
                return "false";

            case TRUE:
                return "true";

            default:
                assert_not_reached();
        }
    }
}

