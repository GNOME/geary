/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * The base respresentation of an complete IMAP message.
 *
 * By definition, a top-level {@link ListParameter}.  A RootParameters object should never be
 * added to another list.
 *
 * @see ServerResponse
 * @see Command
 */

public class Geary.Imap.RootParameters : Geary.Imap.ListParameter {
    public RootParameters(Parameter? initial = null) {
        base (null, initial);
    }
    
    /**
     * Moves all contained {@link Parameter} objects inside the supplied RootParameters into a
     * new RootParameters.
     *
     * The supplied root object is stripped clean by this call.
     */
    public RootParameters.migrate(RootParameters root) {
        base (null);
        
        adopt_children(root);
    }
    
    /**
     * Returns null if the first parameter is not a StringParameter that resembles a Tag.
     */
    public Tag? get_tag() {
        StringParameter? strparam = get_if_string(0);
        if (strparam == null)
            return null;
        
        if (!Tag.is_tag(strparam))
            return null;
        
        return new Tag.from_parameter(strparam);
    }
    
    /**
     * Returns true if the first parameter is a StringParameter that resembles a Tag.
     */
    public bool has_tag() {
        StringParameter? strparam = get_if_string(0);
        if (strparam == null)
            return false;
        
        return (strparam != null) ? Tag.is_tag(strparam) : false;
    }
    
    /**
     * {@inheritDoc}
     */
    public override string to_string() {
        return stringize_list();
    }
    
    /**
     * {@inheritDoc}
     */
    public override void serialize(Serializer ser, Tag tag) throws Error {
        serialize_list(ser, tag);
        ser.push_eol();
    }
}

