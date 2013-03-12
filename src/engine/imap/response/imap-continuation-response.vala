/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.ContinuationResponse : ServerResponse {
    public ContinuationResponse(Tag tag) {
        base (tag);
    }
    
    public ContinuationResponse.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
    }
}

