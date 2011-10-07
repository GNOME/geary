/* Copyright 2011 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

public class Geary.Sqlite.ImapMessagePropertiesRow : Geary.Sqlite.Row {
    public int64 id { get; private set; }
    public int64 message_id { get; private set; }
    public string flags { get; private set; }
    public string internaldate { get; private set; }
    public long rfc822_size { get; private set; }
    
    public ImapMessagePropertiesRow(ImapMessagePropertiesTable table, int64 id, int64 message_id,
        string? flags, string? internaldate, long rfc822_size) {
        base (table);
        
        this.id = id;
        this.message_id = message_id;
        this.flags = flags ?? "";
        this.internaldate = internaldate ?? "";
        this.rfc822_size = rfc822_size;
    }
    
    public ImapMessagePropertiesRow.from_imap_properties(ImapMessagePropertiesTable table,
        int64 message_id, Geary.Imap.EmailProperties properties) {
        base (table);
        
        id = Row.INVALID_ID;
        this.message_id = message_id;
        flags = properties.flags.serialize();
        internaldate = properties.internaldate.original;
        rfc822_size = properties.rfc822_size.value;
    }
    
    public Geary.Imap.EmailProperties get_imap_email_properties() {
        Imap.InternalDate? constructed = null;
        try {
            constructed = new Imap.InternalDate(internaldate);
        } catch (Error err) {
            debug("Unable to construct internaldate object from \"%s\": %s", internaldate,
                err.message);
        }
        
        return new Geary.Imap.EmailProperties(Geary.Imap.MessageFlags.deserialize(flags),
            constructed, new RFC822.Size(rfc822_size));
    }
}

