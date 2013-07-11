/* Copyright 2011-2013 Yorba Foundation
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

public abstract class Geary.EmailIdentifier : BaseObject, Gee.Comparable<Geary.EmailIdentifier>,
    Gee.Hashable<Geary.EmailIdentifier> {
    public int64 ordering { get; protected set; }
    public Geary.FolderPath? folder_path { get; protected set; }
    
    protected EmailIdentifier(int64 ordering, Geary.FolderPath? folder_path) {
        this.ordering = ordering;
        this.folder_path = folder_path;
    }
    
    public virtual uint hash() {
        return Geary.Collection.int64_hash(ordering) ^ (folder_path != null ? folder_path.hash() : 0);
    }
    
    public virtual bool equal_to(Geary.EmailIdentifier other) {
        if (this == other)
            return true;
        
        if (get_type() != other.get_type())
            return false;
        
        if (ordering != other.ordering)
            return false;
        
        if (folder_path != null && other.folder_path != null)
            return folder_path.equal_to(other.folder_path);
        return (folder_path == null && other.folder_path == null);
    }
    
    public virtual int compare_to(Geary.EmailIdentifier other) {
        // Arbitrary type-based ordering, so we never accidentally compare two
        // different types of EmailIdentifier in an unpredictable way.
        if (get_type() != other.get_type())
            return (int) ((long) get_type() - (long) other.get_type()).clamp(-1, 1);
        
        if (folder_path != null && other.folder_path != null) {
            if (!folder_path.equal_to(other.folder_path))
                return folder_path.compare_to(other.folder_path);
        } else if (folder_path != null || other.folder_path != null) {
            // Arbitrarily, folderless ids come after ones with folder.
            return (folder_path == null ? 1 : -1);
        }
        
        return (int) (ordering - other.ordering).clamp(-1, 1);
    }
    
    public virtual int desc_compare_to(Geary.EmailIdentifier other) {
        return -compare_to(other);
    }
    
    public virtual string to_string() {
        return "%s(%s)".printf(ordering.to_string(),
            (folder_path == null ? "null" : folder_path.to_string()));
    }
}

