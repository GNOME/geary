/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.OutboxEmailIdentifier : Geary.EmailIdentifier {
    public OutboxEmailIdentifier(int64 ordering) {
        base (ordering);
    }
    
    public override bool equals(Geary.Equalable o) {
        EmailIdentifier? other = o as EmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return ordering == other.ordering;
    }
}

