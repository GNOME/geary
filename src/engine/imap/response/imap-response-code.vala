/* Copyright 2016 Software Freedom Conservancy Inc.
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
    public ResponseCode() {
    }

    public ResponseCodeType get_response_code_type() throws ImapError {
        return new ResponseCodeType.from_parameter(get_as_string(0));
    }

    /**
     * Converts the {@link ResponseCode} into a UIDNEXT {@link UID}, if possible.
     *
     * @throws ImapError.INVALID if not UIDNEXT.
     */
    public UID get_uid_next() throws ImapError {
        if (!get_response_code_type().is_value(ResponseCodeType.UIDNEXT))
            throw new ImapError.INVALID("Not UIDNEXT: %s", to_string());

        return new UID.checked(get_as_string(1).as_int64());
    }

    /**
     * Converts the {@link ResponseCode} into a {@link UIDValidity}, if possible.
     *
     * @throws ImapError.INVALID if not UIDVALIDITY.
     */
    public UIDValidity get_uid_validity() throws ImapError {
        if (!get_response_code_type().is_value(ResponseCodeType.UIDVALIDITY))
            throw new ImapError.INVALID("Not UIDVALIDITY: %s", to_string());

        return new UIDValidity.checked(get_as_string(1).as_int64());
    }

    /**
     * Converts the {@link ResponseCode} into an UNSEEN value, if possible.
     *
     * @throws ImapError.INVALID if not UNSEEN.
     */
    public int get_unseen() throws ImapError {
        if (!get_response_code_type().is_value(ResponseCodeType.UNSEEN))
            throw new ImapError.INVALID("Not UNSEEN: %s", to_string());

        return get_as_string(1).as_int32(0, int.MAX);
    }

    /**
     * Converts the {@link ResponseCode} into PERMANENTFLAGS {@link MessageFlags}, if possible.
     *
     * @throws ImapError.INVALID if not PERMANENTFLAGS.
     */
    public MessageFlags get_permanent_flags() throws ImapError {
        if (!get_response_code_type().is_value(ResponseCodeType.PERMANENT_FLAGS))
            throw new ImapError.INVALID("Not PERMANENTFLAGS: %s", to_string());

        return MessageFlags.from_list(get_as_list(1));
    }

    /**
     * Parses the {@link ResponseCode} into {@link Capabilities}, if possible.
     *
     * @throws ImapError.INVALID if Capability was not specified.
     */
    public Capabilities get_capabilities(int revision) throws ImapError {
        if (!get_response_code_type().is_value(ResponseCodeType.CAPABILITY))
            throw new ImapError.INVALID("Not CAPABILITY response code: %s", to_string());

        var params = new StringParameter[this.size];
        int count = 0;
        for (int ctr = 1; ctr < size; ctr++) {
            StringParameter? param = get_if_string(ctr);
            if (param != null) {
                params[count++] = param;
            }
        }

        return new Capabilities(params[0:count], revision);
    }

    /**
     * Parses the {@link ResponseCode} into UIDPLUS' COPYUID response, if possible.
     *
     * Note that the {@link UID}s are returned from the server in the order the messages
     * were copied.
     *
     * See [[http://tools.ietf.org/html/rfc4315#section-3]]
     *
     * @throws ImapError.INVALID if not COPYUID.
     */
    public void get_copyuid(out UIDValidity uidvalidity, out Gee.List<UID>? source_uids,
        out Gee.List<UID>? destination_uids) throws ImapError {
        if (!get_response_code_type().is_value(ResponseCodeType.COPYUID))
            throw new ImapError.INVALID("Not COPYUID response code: %s", to_string());

        uidvalidity = new UIDValidity.checked(get_as_number(1).as_int64());
        source_uids = MessageSet.uid_parse(get_as_string(2).ascii);
        destination_uids = MessageSet.uid_parse(get_as_string(3).ascii);
    }

    public override string to_string() {
        return "[%s]".printf(stringize_list());
    }

    public override void serialize(Serializer ser, GLib.Cancellable cancellable)
        throws GLib.Error {
        ser.push_ascii('[', cancellable);
        serialize_list(ser, cancellable);
        ser.push_ascii(']', cancellable);
    }
}
