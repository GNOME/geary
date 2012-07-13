/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Capabilities : Geary.GenericCapabilities {

    /**
     * Creates an empty set of capabilities.
     */
    public Capabilities() {
    }

    public bool add_parameter(StringParameter stringp) {
        string[] tokens = stringp.value.split("=", 2);
        if (tokens.length == 1)
            map.set(tokens[0], null);
        else if (tokens.length == 2)
            map.set(tokens[0], tokens[1]);
        else
            return false;
        
        return true;
    }

    /**
     * Like get_setting(), but returns a StringParameter representing the capability.
     */
    public StringParameter? get_parameter(string name) {
        string? setting = map.get(name);
        
        return new StringParameter(String.is_empty(setting) ? name : "%s=%s".printf(name, setting));
    }
}

