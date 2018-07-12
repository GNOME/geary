/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A representation of an IMAP command (request).
 *
 * A Command is created by the caller and then submitted to a {@link ClientSession} or
 * {@link ClientConnection} for transmission to the server.  In response, one or more
 * {@link ServerResponse}s are returned, generally zero or more {@link ServerData}s followed by
 * a completion {@link StatusResponse}.  Untagged {@link StatusResponse}s may also be returned,
 * depending on the Command.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-6]]
 */

public class Geary.Imap.Command : BaseObject {

    /**
     * All IMAP commands are tagged with an identifier assigned by the client.
     *
     * Note that this is not immutable.  The general practice is to use an unassigned Tag
     * up until the {@link Command} is about to be transmitted, at which point a Tag is
     * assigned.  This allows for all commands to be issued in Tag "order".  This generally makes
     * tracing network traffic easier.
     *
     * @see Tag.get_unassigned
     * @see assign_tag
     */
    public Tag tag { get; private set; }

    /**
     * The name (or "verb") of the {@link Command}.
     */
    public string name { get; private set; }

    /**
     * The command's arguments as parameters.
     *
     * Subclassess may append arguments to this before {@link
     * serialize} is called, ideally from the constructor.
     */
    protected ListParameter args {
        get; private set; default = new RootParameters();
    }
    /**
     * Constructs a new command with an unassigned tag.
     *
     * Any arguments provided here will be converted to appropriate
     * string arguments
     *
     * @see Tag
     */
    public Command(string name, string[]? args = null) {
        tag = Tag.get_unassigned();
        this.name = name;
        if (args != null) {
            foreach (string arg in args) {
                this.args.add(Parameter.get_for_string(arg));
            }
        }
    }
    
    /**
     *
     */
    }
    
    private void stock_params() {
        add(tag);
        add(new AtomParameter(name));
        if (args != null) {
            foreach (string arg in args)
                add(Parameter.get_for_string(arg));
        }
    }
    
    /**
     * Assign a {@link Tag} to a {@link Command} with an unassigned placeholder Tag.
     *
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
        return Ascii.stri_equal(this.name, name);
    }
    
    public override void serialize(Serializer ser, Tag tag) throws Error {
        assert(tag.is_assigned());
        
        base.serialize(ser, tag);
        ser.push_end_of_message();
    }
}

