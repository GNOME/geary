/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A tagged IMAP {@link StatusResponse} which indicates that the associated {@link Command} has
 * completed.
 *
 * By IMAP definition, the {@link Status} of a CompletionStatusResponse can only be OK, NO, or BAD.
 * Other statuses are reserved for untagged responses.
 *
 * See [[http://tools.ietf.org/html/rfc3501#section-7]] for more information.
 */

public class Geary.Imap.CompletionStatusResponse : StatusResponse {
    public CompletionStatusResponse(Tag tag, Status status) {
        base (tag, status);
    }
    
    /**
     * Converts the {@link RootParameters} into a {@link CompletionStatusResponse}.
     *
     * The supplied root is "stripped" of its children.  This may happen even if an exception is
     * thrown.  It's recommended to use {@link is_completion_status_response} prior to this call.
     */
    public CompletionStatusResponse.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
        
        // check this is actually a CompletionStatusResponse
        if (!tag.is_tagged()) {
            throw new ImapError.INVALID("Not a CompletionStatusResponse: untagged response: %s",
                root.to_string());
        }
        
        switch (status) {
            case Status.OK:
            case Status.NO:
            case Status.BAD:
                // looks good
            break;
            
            default:
                throw new ImapError.INVALID("Not a CompletionStatusResponse: not OK, NO, or BAD: %s",
                    root.to_string());
        }
    }
    
    /**
     * Returns true if {@link RootParameters} is a tagged {@link StatusResponse} with a
     * {@link Status} of OK, NO, or BAD.
     */
    public static bool is_completion_status_response(RootParameters root) {
        Tag? tag = root.get_tag();
        if (tag == null || !tag.is_tagged())
            return false;
        
        // TODO: Is this too stringent?  It means a faulty server could send back a completion
        // with another Status code and cause the client to treat the command as "unanswered",
        // requiring a timeout.
        try {
            switch (Status.from_parameter(root.get_as_string(1))) {
                case Status.OK:
                case Status.NO:
                case Status.BAD:
                    // fall through
                break;
                
                default:
                    return false;
            }
        } catch (ImapError err) {
            return false;
        }
        
        return is_status_response(root);
    }
}

