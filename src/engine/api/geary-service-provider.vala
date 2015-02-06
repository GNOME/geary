/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of the various built-in email service providers Geary supports.
 */

public enum Geary.ServiceProvider {
    GMAIL,
    YAHOO,
    OUTLOOK,
    OTHER;
    
    public static ServiceProvider[] get_providers() {
        return { GMAIL, YAHOO, OUTLOOK, OTHER };
    }
    
    /**
     * Returns the service provider in a serialized form.
     *
     * @see from_string
     */
    public string to_string() {
        switch (this) {
            case GMAIL:
                return "GMAIL";
            
            case YAHOO:
                return "YAHOO";
            
            case OUTLOOK:
                return "OUTLOOK";
            
            case OTHER:
                return "OTHER";
            
            default:
                assert_not_reached();
        }
    }
    
    /**
     * Returns the service provider's name in a translated UTF-8 string suitable for display to the
     * user.
     */
    public string display_name() {
        switch (this) {
            case GMAIL:
                return _("Gmail");
            
            case YAHOO:
                return _("Yahoo! Mail");
            
            case OUTLOOK:
                return _("Outlook.com");
            
            case OTHER:
                return _("Other");
            
            default:
                assert_not_reached();
        }
    }
    
    /**
     * Converts a string form of the service provider (returned by {@link to_string} to a
     * {@link ServiceProvider} value.
     *
     * @see to_string
     */
    public static ServiceProvider from_string(string str) {
        switch (str.up()) {
            case "GMAIL":
                return GMAIL;
            
            case "YAHOO":
                return YAHOO;
            
            case "OUTLOOK":
                return OUTLOOK;
            
            case "OTHER":
                return OTHER;
            
            default:
                assert_not_reached();
        }
    }
}

