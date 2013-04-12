/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Imap.ServerData : ServerResponse {
    public ServerData(Tag tag) {
        base (tag);
    }
    
    public ServerData.migrate(RootParameters root) throws ImapError {
        base.migrate(root);
    }
}

