/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A response line from the server indicating either a result from a command or an unsolicited
 * change in state.
 *
 * StatusResponses may be tagged or untagged, depending on their nature.  See
 * {@link CompletionStatusResponse} and {@link CodedStatusResponse} for special types of
 * StatusResponses.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7.1]] for more information.
 *
 * @see ServerResponse.migrate_from_server
 */

public class Geary.Imap.StatusResponse : ServerResponse {
    public Status status { get; private set; }
    
    public StatusResponse(Tag tag, Status status) {
        base (tag);
        
        this.status = status;
    }
    
    /**
     * Converts the {@link RootParameters} into a {@link StatusResponse}.
     *
     * The supplied root is "stripped" of its children.  This may happen even if an exception is
     * thrown.  It's recommended to use {@link is_status_response} prior to this call.
     */
    public StatusResponse.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
        
        status = Status.from_parameter(get_as_string(1));
    }
    
    /**
     * Returns optional text provided by the server.  Note that this text is not internationalized
     * and probably in English, and is not standard or uniformly declared.  It's not recommended
     * this text be displayed to the user.
     */
    public string? get_text() {
        // build text from all StringParameters ... this will skip any ResponseCode or ListParameter
        // (or NilParameter, for that matter)
        StringBuilder builder = new StringBuilder();
        for (int index = 2; index < get_count(); index++) {
            StringParameter? strparam = get_if_string(index);
            if (strparam != null) {
                builder.append(strparam.value);
                if (index < (get_count() - 1))
                    builder.append_c(' ');
            }
        }
        
        return !String.is_empty(builder.str) ? builder.str : null;
    }
    
    /**
     * Returns true if {@link RootParameters} holds a {@link Status} parameter.
     */
    public static bool is_status_response(RootParameters root) {
        if (!root.has_tag())
            return false;
        
        try {
            Status.from_parameter(root.get_as_string(1));
            
            return true;
        } catch (ImapError err) {
            return false;
        }
    }
}

