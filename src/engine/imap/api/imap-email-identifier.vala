/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

private class Geary.Imap.EmailIdentifier : Geary.EmailIdentifier {
    public Imap.UID uid { get; private set; }
    
    public EmailIdentifier(Imap.UID uid) {
        base (uid.value);
        
        this.uid = uid;
    }
    
    public override uint to_hash() {
        return Geary.Hashable.int64_hash(uid.value);
    }
    
    public override bool equals(Equalable o) {
        Geary.Imap.EmailIdentifier? other = o as Geary.Imap.EmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return ordering == other.ordering;
    }
    
    public override string to_string() {
        return uid.to_string();
    }
}

