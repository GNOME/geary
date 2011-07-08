/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapMessagePropertiesRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 message_id { get; private set; }
    public string flags { get; private set; }
    
    public ImapMessagePropertiesRow(ImapMessagePropertiesTable table, int64 id, int64 message_id,
        string flags) {
        base (table);
        
        this.id = id;
        this.message_id = message_id;
        this.flags = flags;
    }
    
    public ImapMessagePropertiesRow.from_imap_properties(ImapMessagePropertiesTable table,
        int64 message_id, Geary.Imap.EmailProperties properties) {
        base (table);
        
        id = Row.INVALID_ID;
        this.message_id = message_id;
        flags = properties.flags.serialize();
    }
    
    public Geary.Imap.EmailProperties get_imap_email_properties() {
        return new Geary.Imap.EmailProperties(Geary.Imap.MessageFlags.deserialize(flags));
    }
}

