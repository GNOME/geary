/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.EmailIdentifier : Geary.EmailIdentifier {
    public EmailIdentifier(int64 message_id) {
        base (message_id);
    }
    
    public override bool equal_to(Geary.EmailIdentifier o) {
        Geary.ImapDB.EmailIdentifier? other = o as Geary.ImapDB.EmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return ordering == other.ordering;
    }
}
