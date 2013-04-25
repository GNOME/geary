/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.SmtpOutboxEmailIdentifier : Geary.EmailIdentifier {
    public SmtpOutboxEmailIdentifier(int64 ordering) {
        base (ordering);
    }
    
    public override bool equal_to(Geary.EmailIdentifier o) {
        SmtpOutboxEmailIdentifier? other = o as SmtpOutboxEmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return ordering == other.ordering;
    }
}

