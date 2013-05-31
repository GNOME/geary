/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A response code and additional information that optionally accompanies a {@link StatusResponse}.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.1]] for more information.
 */

public class Geary.Imap.ResponseCode : Geary.Imap.ListParameter {
    public ResponseCode(ListParameter parent, Parameter? initial = null) {
        base (parent, initial);
    }
    
    public ResponseCodeType get_response_code_type() throws ImapError {
        return ResponseCodeType.from_parameter(get_as_string(0));
    }
    
    /**
     * Converts the {@link ResponseCode} into a UIDNEXT {@link UID}, if possible.
     *
     * @throws ImapError.INVALID if not UIDNEXT.
     */
    public UID get_uid_next() throws ImapError {
        if (get_response_code_type() != ResponseCodeType.UIDNEXT)
            throw new ImapError.INVALID("Not UIDNEXT: %s", to_string());
        
        return new UID(get_as_string(1).as_int());
    }
    
    /**
     * Converts the {@link ResponseCode} into a {@link UIDValidity}, if possible.
     *
     * @throws ImapError.INVALID if not UIDVALIDITY.
     */
    public UIDValidity get_uid_validity() throws ImapError {
        if (get_response_code_type() != ResponseCodeType.UIDVALIDITY)
            throw new ImapError.INVALID("Not UIDVALIDITY: %s", to_string());
        
        return new UIDValidity(get_as_string(1).as_int());
    }
    
    /**
     * Converts the {@link ResponseCode} into an UNSEEN value, if possible.
     *
     * @throws ImapError.INVALID if not UNSEEN.
     */
    public int get_unseen() throws ImapError {
        if (get_response_code_type() != ResponseCodeType.UNSEEN)
            throw new ImapError.INVALID("Not UNSEEN: %s", to_string());
        
        return get_as_string(1).as_int(0, int.MAX);
    }
    
    /**
     * Converts the {@link ResponseCode} into PERMANENTFLAGS {@link MessageFlags}, if possible.
     *
     * @throws ImapError.INVALID if not PERMANENTFLAGS.
     */
    public MessageFlags get_permanent_flags() throws ImapError {
        if (get_response_code_type() != ResponseCodeType.PERMANENT_FLAGS)
            throw new ImapError.INVALID("Not PERMANENTFLAGS: %s", to_string());
        
        return MessageFlags.from_list(get_as_list(1));
    }
    
    /**
     * Parses the {@link ResponseCode} into {@link Capabilities}, if possible.
     *
     * Since Capabilities are revised with various {@link ClientSession} states, this method accepts
     * a ref to an int that will be incremented after handed to the Capabilities constructor.  This
     * can be used to track the revision of capabilities seen on the connection.
     *
     * @throws ImapError.INVALID if Capability was not specified.
     */
    public Capabilities get_capabilities(ref int next_revision) throws ImapError {
        if (get_response_code_type() != ResponseCodeType.CAPABILITY)
            throw new ImapError.INVALID("Not CAPABILITY response code: %s", to_string());
        
        Capabilities capabilities = new Capabilities(next_revision++);
        for (int ctr = 1; ctr < get_count(); ctr++) {
            StringParameter? param = get_if_string(ctr);
            if (param != null)
                capabilities.add_parameter(param);
        }
        
        return capabilities;
    }
    
    public override string to_string() {
        return "[%s]".printf(stringize_list());
    }
    
    public override async void serialize(Serializer ser) throws Error {
        ser.push_ascii('[');
        yield serialize_list(ser);
        ser.push_ascii(']');
    }
}

