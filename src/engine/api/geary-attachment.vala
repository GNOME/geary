/* Copyright 2011-2013 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * An attachment that was a part of an {@link Email}.
 *
 * @see Email.get_attachment
 */

public abstract class Geary.Attachment : BaseObject {
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
    
    /**
     * An identifier that can be used to locate the {@link Attachment} in an {@link Email}.
     *
     * @see Email.get_attachment
     */
    public string id { get; private set; }
    
    /**
     * Returns true if the originating {@link Email} supplied a filename for the {@link Attachment}.
     *
     * Since all files must have a name, one is supplied for the Attachment by Geary if this is
     * false.  This is merely to indicate how the filename should be displayed, since Geary's will
     * be an untranslated "none".
     */
    public bool has_supplied_filename { get; private set; }
    
    /**
     * The on-disk File of the {@link Attachment}.
     */
    public File file { get; private set; }
    
    /**
     * The MIME type of the {@link Attachment}.
     */
    public string mime_type { get; private set; }
    
    /**
     * The file size (in bytes) if the {@link file}.
     */
    public int64 filesize { get; private set; }
    
    /**
     * The {@link Disposition} of the attachment, as specified by the {@link Email}.
     *
     * See [[https://tools.ietf.org/html/rfc2183]]
     */
    public Disposition disposition { get; private set; }
    
    protected Attachment(string id, File file, bool has_supplied_filename, string mime_type, int64 filesize,
        Disposition disposition) {
        this.id = id;
        this.file = file;
        this.has_supplied_filename = has_supplied_filename;
        this.mime_type = mime_type;
        this.filesize = filesize;
        this.disposition = disposition;
    }
}

