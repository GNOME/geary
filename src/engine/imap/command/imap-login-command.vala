/* Copyright 2011-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://tools.ietf.org/html/rfc3501#section-6.2.3]]
 */

public class Geary.Imap.LoginCommand : Command {
    public const string NAME = "login";
    
    public LoginCommand(string user, string pass) {
        base (NAME, { user, pass });
    }
    
    public override string to_string() {
        return "%s %s <user> <pass>".printf(tag.to_string(), name);
    }
}

