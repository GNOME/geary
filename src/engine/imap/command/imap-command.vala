/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Command : RootParameters {
    public Tag tag { get; private set; }
    public string name { get; private set; }
    public string[]? args { get; private set; }
    
    public Command(Tag tag, string name, string[]? args = null) requires (tag.is_tagged()) {
        this.tag = tag;
        this.name = name;
        this.args = args;
        
        add(tag);
        add(new UnquotedStringParameter(name));
        if (args != null) {
            foreach (string arg in args)
                add(new StringParameter(arg));
        }
    }
    
    public bool has_name(string name) {
        return this.name.down() == name.down();
    }
}

