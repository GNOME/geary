/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

/**
 * Each mail system must have its own method for uniquely identifying an email message.  The only
 * limitation upon an EmailIdentifier is that it's only considered valid within the Folder the
 * message is located in; an EmailIdentifier cannot be used in another Folder to determine if the
 * message is duplicated there.  (Either EmailIdentifier will be expanded to allow for this or
 * another system will be offered.)
 *
 * EmailIdentifier is Comparable because it can be used to compare against other EmailIdentifiers
 * (in the same Folder) for sort order that corresponds to their position in the Folder.  It does
 * this through an ordering field that provides an integer that can be compared to other ordering
 * fields in the same Folder that match the email's position within it.  The ordering field may
 * or may not be the actual unique identifier; in IMAP, for example, it is, while in other systems
 * it may not be.
 */

public abstract class Geary.EmailIdentifier : Object, Geary.Equalable, Geary.Comparable, Geary.Hashable {
    public abstract int64 ordering { get; protected set; }
    
    public abstract bool equals(Geary.Equalable other);
    
    public abstract uint to_hash();
    
    public virtual int compare(Geary.Comparable o) {
        Geary.EmailIdentifier? other = o as Geary.EmailIdentifier;
        if (other == null)
            return -1;
        
        if (this == other)
            return 0;
        
        int64 diff = ordering - other.ordering;
        if (diff < 0)
            return -1;
        else if (diff > 0)
            return 1;
        else
            return 0;
    }
    
    public abstract string to_string();
}

