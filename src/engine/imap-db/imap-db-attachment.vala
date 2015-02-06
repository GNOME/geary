/* Copyright 2013-2015 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

private class Geary.ImapDB.Attachment : Geary.Attachment {
    public const Email.Field REQUIRED_FIELDS = Email.REQUIRED_FOR_MESSAGE;
    
    private const string ATTACHMENTS_DIR = "attachments";
    
    protected Attachment(File data_dir, string? filename, Mime.ContentType content_type, int64 filesize,
        int64 message_id, int64 attachment_id, Mime.ContentDisposition content_disposition,
        string? content_id, string? content_description) {
        base (generate_id(attachment_id),generate_file(data_dir, message_id, attachment_id, filename),
            !String.is_empty(filename), content_type, filesize, content_disposition, content_id,
            content_description);
    }
    
    private static string generate_id(int64 attachment_id) {
        return "imap-db:%s".printf(attachment_id.to_string());
    }
    
    public static File generate_file(File data_dir, int64 message_id, int64 attachment_id,
        string? filename) {
        // "none" should not be translated, or the user will be unable to retrieve their
        // attachments with no filenames after changing their language.
        return get_attachments_dir(data_dir)
            .get_child(message_id.to_string())
            .get_child(attachment_id.to_string())
            .get_child(filename ?? "none");
    }
    
    public static File get_attachments_dir(File data_dir) {
        return data_dir.get_child(ATTACHMENTS_DIR);
    }
}
