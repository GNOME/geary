/* Copyright 2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.CompletionStatusResponse : StatusResponse {
    private CompletionStatusResponse() {
    }
    
    public CompletionStatusResponse.reconstitute(RootParameters root) throws ImapError {
        base.reconstitute(root);
        
        // check this is actually a CompletionStatusResponse
        if (!tag.is_tagged()) {
            throw new ImapError.PARSE_ERROR("Not a CompletionStatusResponse: untagged response: %s",
                root.to_string());
        }
        
        switch (status) {
            case Status.OK:
            case Status.NO:
            case Status.BAD:
                // looks good
            break;
            
            default:
                throw new ImapError.PARSE_ERROR("Not a CompletionStatusResponse: not OK, NO, or BAD: %s",
                    root.to_string());
        }
    }
}

