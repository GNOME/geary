/* Copyright 2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Capabilities : Geary.GenericCapabilities {
    public const string STARTTLS = "STARTTLS";
    public const string COMPRESS = "COMPRESS";
    public const string DEFLATE_SETTING = "DEFLATE";
    
    public int revision { get; private set; }
    
    /**
     * Creates an empty set of capabilities.  revision represents the different variations of
     * capabilities that an IMAP session might offer (i.e. changes after login or STARTTLS, for
     * example).
     */
    public Capabilities(int revision) {
        this.revision = revision;
    }

    public bool add_parameter(StringParameter stringp) {
        string[] tokens = stringp.value.split("=", 2);
        if (tokens.length == 1)
            add_capability(tokens[0]);
        else if (tokens.length == 2)
            add_capability(tokens[0], tokens[1]);
        else
            return false;
        
        return true;
    }

    /**
     * Like get_setting(), but returns a StringParameter representing the capability.
     */
    public StringParameter? get_parameter(string name) {
        string? setting = get_setting(name);
        
        return new StringParameter(String.is_empty(setting) ? name : "%s=%s".printf(name, setting));
    }
    
    public override string to_string() {
        return "#%d: %s".printf(revision, base.to_string());
    }
}

