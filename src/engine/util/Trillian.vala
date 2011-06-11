/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * A trillian is a three-state boolean, used when the value is potentially unknown.
 */

public enum Geary.Trillian {
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
    
    public int to_int() {
        return (int) this;
    }
    
    public inline static Trillian from_int(int i) {
        switch (i) {
            case 0:
                return FALSE;
            
            case 1:
                return TRUE;
            
            default:
                return UNKNOWN;
        }
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

