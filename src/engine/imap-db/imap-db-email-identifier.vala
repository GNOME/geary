/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.EmailIdentifier : Geary.EmailIdentifier {
    public Geary.FolderPath? folder_path { get; private set; }
    
    public EmailIdentifier(int64 message_id, Geary.FolderPath? folder_path) {
        base (message_id);
        
        this.folder_path = folder_path;
    }
    
    public override Geary.FolderPath? get_folder_path() {
        return folder_path;
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
