/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public enum Geary.ServiceProvider {
    GMAIL,
    YAHOO,
    OTHER;
    
    public static ServiceProvider[] get_providers() {
        return { GMAIL, YAHOO, OTHER };
    }
    
    public string to_string() {
        switch (this) {
            case GMAIL:
                return "GMAIL";
            
            case YAHOO:
                return "YAHOO";
            
            case OTHER:
                return "OTHER";
            
            default:
                assert_not_reached();
        }
    }
    
    public string display_name() {
        switch (this) {
            case GMAIL:
                return _("Gmail");
            
            case YAHOO:
                return _("Yahoo! Mail");
            
            case OTHER:
                return _("Other");
            
            default:
                assert_not_reached();
        }
    }
    
    public static ServiceProvider from_string(string str) {
        switch (str.up()) {
            case "GMAIL":
                return GMAIL;
            
            case "YAHOO":
                return YAHOO;
            
            case "OTHER":
                return OTHER;
            
            default:
                assert_not_reached();
        }
    }
}

