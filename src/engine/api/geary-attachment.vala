/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class Geary.Attachment : BaseObject {
    public const Email.Field REQUIRED_FIELDS = Email.REQUIRED_FOR_MESSAGE;
    
    // NOTE: These values are persisted on disk and should not be modified unless you know what
    // you're doing.
    public enum Disposition {
        ATTACHMENT = 0,
        INLINE = 1;
        
        public static Disposition? from_string(string? str) {
            // Returns null to indicate an unknown disposition
            if (str == null) {
                return null;
            }
            
            switch (str.down()) {
                case "attachment":
                    return ATTACHMENT;
                
                case "inline":
                    return INLINE;
                
                default:
                    return null;
            }
        }
        
        public static Disposition from_int(int i) {
            switch (i) {
                case INLINE:
                    return INLINE;
                
                case ATTACHMENT:
                default:
                    return ATTACHMENT;
            }
        }
    }
    
    public string? filename { get; private set; }
    public string filepath { get; private set; }
    public string mime_type { get; private set; }
    public int64 filesize { get; private set; }
    public int64 id { get; private set; }
    public Disposition disposition { get; private set; }
    
    // TODO: Move some of this into ImapDB.Attachment
    internal Attachment(File data_dir, string? filename, string mime_type, int64 filesize,
        int64 message_id, int64 attachment_id, Disposition disposition) {

        this.filename = filename;
        this.mime_type = mime_type;
        this.filesize = filesize;
        this.filepath = get_path(data_dir, message_id, attachment_id, filename);
        this.id = attachment_id;
        this.disposition = disposition;
    }
    
    // TODO: Move this into ImapDB.Attachment
    internal static string get_path(File data_dir, int64 message_id, int64 attachment_id,
        string? filename) {
        // "none" should not be translated, or the user will be unable to retrieve their
        // attachments with no filenames after changing their language.
        return "%s/attachments/%s/%s/%s".printf(data_dir.get_path(), message_id.to_string(),
            attachment_id.to_string(), filename ?? "none");
    }
    
    internal static File get_attachments_dir(File data_dir) {
        return data_dir.get_child("attachments");
    }
}

