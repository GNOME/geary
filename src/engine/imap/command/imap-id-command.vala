/* Copyright 2011-2014 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * See [[http://www.ietf.org/rfc/rfc2971.txt]]
 */

public class Geary.Imap.IdCommand : Command {
    public const string NAME = "id";
    
    public IdCommand(Gee.HashMap<string, string> fields) {
        base (NAME);
        
        ListParameter list = new ListParameter();
        foreach (string key in fields.keys) {
            list.add(new QuotedStringParameter(key));
            list.add(new QuotedStringParameter(fields.get(key)));
        }
        
        add(list);
    }
    
    public IdCommand.nil() {
        base (NAME);
        
        add(NilParameter.instance);
    }
}

