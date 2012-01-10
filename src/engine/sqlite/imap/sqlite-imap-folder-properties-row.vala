/* Copyright 2011-2012 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapFolderPropertiesRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 folder_id { get; private set; }
    public int last_seen_total { get; private set; }
    public Geary.Imap.UIDValidity? uid_validity { get; private set; }
    public Geary.Imap.UID? uid_next { get; private set; }
    public string attributes { get; private set; }
    
    public ImapFolderPropertiesRow(ImapFolderPropertiesTable table, int64 id, int64 folder_id,
        int last_seen_total, Geary.Imap.UIDValidity? uid_validity, Geary.Imap.UID? uid_next,
        string? attributes) {
        base (table);
        
        this.id = id;
        this.folder_id = folder_id;
        this.last_seen_total = last_seen_total;
        this.uid_validity = uid_validity;
        this.uid_next = uid_next;
        this.attributes = attributes ?? "";
    }
    
    public ImapFolderPropertiesRow.from_imap_properties(ImapFolderPropertiesTable table,
        int64 folder_id, Geary.Imap.FolderProperties properties) {
        base (table);
        
        id = Row.INVALID_ID;
        this.folder_id = folder_id;
        last_seen_total = properties.messages;
        uid_validity = properties.uid_validity;
        uid_next = properties.uid_next;
        attributes = properties.attrs.serialize();
    }
    
    public Geary.Imap.FolderProperties get_imap_folder_properties() {
        return new Geary.Imap.FolderProperties(last_seen_total, 0, 0, uid_validity, uid_next,
            Geary.Imap.MailboxAttributes.deserialize(attributes));
    }
}

