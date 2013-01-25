/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ContinuationResponse : ServerResponse {
    public ContinuationResponse.reconstitute(RootParameters root) throws ImapError {
        base.reconstitute(root);
        
        if (!tag.is_continuation())
            throw new ImapError.PARSE_ERROR("Not a continuation: %s", to_string());
    }
    
    public static bool is_continuation_response(RootParameters root) {
        Tag? tag = root.get_tag();
        
        return (tag != null && tag.is_continuation());
    }
}

