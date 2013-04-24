/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.Imap.EmailIdentifier : Geary.EmailIdentifier {
    public Imap.UID uid { get; private set; }
    public Geary.FolderPath folder_path { get; private set; }
    
    public EmailIdentifier(Imap.UID uid, Geary.FolderPath folder_path) {
        base (uid.value);
        
        this.uid = uid;
        this.folder_path = folder_path;
    }
    
    public override Geary.FolderPath? get_folder_path() {
        return folder_path;
    }
    
    public override uint to_hash() {
        return uid.to_hash();
    }
    
    public override bool equals(Equalable o) {
        Geary.Imap.EmailIdentifier? other = o as Geary.Imap.EmailIdentifier;
        if (other == null)
            return false;
        
        if (this == other)
            return true;
        
        return uid.equals(other.uid) && folder_path.equals(other.folder_path);
    }
    
    public override string to_string() {
        return uid.to_string();
    }
}

