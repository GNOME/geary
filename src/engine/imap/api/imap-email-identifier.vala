/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.Imap.EmailIdentifier : Geary.EmailIdentifier {
    public Imap.UID uid { get; private set; }
    
    public EmailIdentifier(Imap.UID uid, Geary.FolderPath folder_path) {
        base (uid.value, folder_path);
        
        this.uid = uid;
    }
    
    public override string to_string() {
        return "%s(%s)".printf(uid.to_string(),
            (folder_path == null ? "null" : folder_path.to_string()));
    }
}

