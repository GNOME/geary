/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.EmailIdentifier : Geary.EmailIdentifier {
    public Imap.UID uid { get; private set; }
    
    public EmailIdentifier(Imap.UID uid) {
        this.uid = uid;
    }
    
    public override bool equals(Equalable o) {
        Geary.Imap.EmailIdentifier? other = o as Geary.Imap.EmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return uid.value == other.uid.value;
    }
    
    public override string to_string() {
        return uid.to_string();
    }
}

