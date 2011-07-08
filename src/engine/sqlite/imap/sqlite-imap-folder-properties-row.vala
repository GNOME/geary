/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapFolderPropertiesRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 folder_id { get; private set; }
    public Geary.Imap.UIDValidity? uid_validity { get; private set; }
    public string attributes { get; private set; }
    
    public ImapFolderPropertiesRow(ImapFolderPropertiesTable table, int64 id, int64 folder_id,
        Geary.Imap.UIDValidity? uid_validity, string attributes) {
        base (table);
        
        this.id = id;
        this.folder_id = folder_id;
        this.uid_validity = uid_validity;
        this.attributes = attributes;
    }
    
    public ImapFolderPropertiesRow.from_imap_properties(ImapFolderPropertiesTable table,
        int64 folder_id, Geary.Imap.FolderProperties properties) {
        base (table);
        
        id = Row.INVALID_ID;
        this.folder_id = folder_id;
        uid_validity = properties.uid_validity;
        attributes = properties.attrs.serialize();
    }
    
    public Geary.Imap.FolderProperties get_imap_folder_properties() {
        return new Geary.Imap.FolderProperties(uid_validity,
            Geary.Imap.MailboxAttributes.deserialize(attributes));
    }
}

