/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Imap.EmailProperties : Geary.EmailProperties, Equalable {
    public InternalDate? internaldate { get; private set; }
    public RFC822.Size? rfc822_size { get; private set; }
    
    public EmailProperties(InternalDate? internaldate, RFC822.Size? rfc822_size) {
        this.internaldate = internaldate;
        this.rfc822_size = rfc822_size;
    }
    
    public bool equals(Equalable e) {
        Imap.EmailProperties? other = e as Imap.EmailProperties;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        // for simplicity and robustness, internaldate and rfc822_size must be present in both
        // to be considered equal
        if (internaldate == null || other.internaldate == null)
            return false;
        
        if (rfc822_size == null || other.rfc822_size == null)
            return false;
        
        return true;
    }
    
    public override string to_string() {
        return "internaldate:%s/size:%s".printf((internaldate != null) ? internaldate.to_string() : "(none)",
            (rfc822_size != null) ? rfc822_size.to_string() : "(none)");
    }
}

