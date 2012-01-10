/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.Command : RootParameters {
    public Tag tag { get; private set; }
    public string name { get; private set; }
    public string[]? args { get; private set; }
    
    public Command(string name, string[]? args = null) {
        tag = Tag.get_unassigned();
        this.name = name;
        this.args = args;
        
        stock_params();
    }
    
    public Command.assigned(Tag tag, string name, string[]? args = null)
        requires (tag.is_tagged() && tag.is_assigned()) {
        this.tag = tag;
        this.name = name;
        this.args = args;
        
        stock_params();
    }
    
    private void stock_params() {
        add(tag);
        add(new UnquotedStringParameter(name));
        if (args != null) {
            foreach (string arg in args)
                add(new StringParameter(arg));
        }
    }
    
    /**
     * Can only be called on a Command that holds an unassigned Tag.  Thus, this can only be called
     * once at most, and zero times if Command.assigned() was used to generate the Command.
     * Fires an assertion if either of these cases is true, or if the supplied Tag is unassigned.
     */
    public void assign_tag(Tag tag) {
        assert(!this.tag.is_assigned());
        assert(tag.is_assigned());
        
        this.tag = tag;
        
        // Tag is always at index zero.
        try {
            Parameter param = replace(0, tag);
            assert(param is Tag);
        } catch (ImapError err) {
            error("Unable to assign Tag for command %s: %s", to_string(), err.message);
        }
    }
    
    public bool has_name(string name) {
        return this.name.down() == name.down();
    }
    
    public override async void serialize(Serializer ser) throws Error {
        assert(tag.is_assigned());
        
        yield base.serialize(ser);
    }
}

